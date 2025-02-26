#!/bin/bash
# Communicate with Sentry using API and Bash methods

# Use Sentry.io for error reporting:
#   source /usr/lib64/sentry_lib.sh
#   sentry_init 83105fca2e2e2351b01 4508410146651  (sentry.io)
#   sentry_init 8f7152da911 1 bugsink.example.net  (bugsink)
#   sentry_message "Exception" "failed to read mutex" "error"


# sentry_init(API key, project ID, server name)
# Prepare to access the Sentry API using an API key and a project number.
# The server name is optional and defaults to 'sentry.io'.
#
# Example Data Source Name (DSN):
# https://419595dd76021@o4506231.ingest.us.sentry.io/4508864683371
#         ^^^^^^^^^^^^^                              ^^^^^^^^^^^^^
#             key                                     project ID
sentry_init () {
  _SENTRY_KEY=$1
  _SENTRY_PROJECT=$2

  if [ -z "${3}" ] ; then
    _SENTRY_HOST=sentry.io
  else
    _SENTRY_HOST=$3
  fi
}


# generate_uuid()
# Generate a UUID using the OS method, or alternatively a random string.
# Debian uses "uuid" while Red Hat uses "uuidgen"
generate_uuid () {
  if command -v uuid >/dev/null 2>&1 ; then
    echo "$(uuid)"
  elif command -v uuidgen >/dev/null 2>&1 ; then
    echo "$(uuidgen)"
  else
    # craft a UUID using bash methods: 8-4-4-4-12
    printf "%s-%s-%s-%s-%s" \
      $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8) \
      $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 4) \
      $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 4) \
      $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 4) \
      $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 12)
  fi
}


# sentry_message(title, message, severity)
# Report a message to Sentry. The title is mandatory. Message and severity
# are optional. Severity can be: fatal, error, warning, info, and debug
sentry_message () {
  [ -z "${1}" ] && return 1
  title=$1
  message=$2
  severity=$3
  curl_opts=''

  # The Sentry server expects an API key and a project number
  if [ -z "${_SENTRY_KEY}" -o -z "${_SENTRY_PROJECT}" ]; then
    echo "Error: Sentry key or project missing. Run sentry_init() first."
    return 1
  fi
  event_id="$(uuidgen)"
  event_timestamp=$(date --utc +"%Y-%m-%dT%H:%M:%S")

  # The default value for level/severity is 'info'
  if [ -z "${severity}" ] ; then
    severity='info'
  fi
  
  # Define variable _SENTRY_NO_CERTIFICATE_CHECK to ignore the
  # server's TLS certificate.
  if [ ! -z ${_SENTRY_NO_CERTIFICATE_CHECK+1} ] ; then
    curl_opts=--insecure
  fi

  # Contact Sentry API and submit the message
  curl --data "{
    \"event_id\": \"$event_id\",
    \"message\": \"$message\",
    \"timestamp\": \"$event_timestamp\",
    \"level\": \"$severity\",
    \"environment\": \"production\",
    \"platform\": \"$(cat /etc/redhat-release /etc/debian_version 2>/dev/null)\",
    \"tags\": {
      \"shell\": \"$SHELL\",
      \"server_name\": \"`hostname`\",
      \"path\": \"`pwd`\"
    },
    \"exception\": [{
      \"type\": \"$title\",
      \"value\": \"$message\",
      \"module\": \"__builtins__\"
    }],
    \"extra\": {
      \"sys.argv\": \"$SCRIPT_ARGUMENTS\"
    }
  }" \
  $curl_opts \
  --header 'Content-Type: application/json' \
  --header "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$_SENTRY_KEY, sentry_client=zenithal-bash/0.1" \
  https://$_SENTRY_HOST/api/$_SENTRY_PROJECT/store/
}
