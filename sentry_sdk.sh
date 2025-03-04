#!/bin/bash

# Use Sentry.io for error reporting:
#   source /usr/lib64/sentry_sdk.sh
#   sentry_init 83105fca2e2e2351b01 4508410146651  (sentry.io)
#   sentry_init 8f7152da911 1 bugsink.example.net  (bugsink)
#   sentry_event "failed to read mutex" "error"
#   sentry_message "Exception" "failed to read mutex" "error"


# Automatic reporting in case of script failure
trap sentry_trap_err ERR


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


# sentry_trap_err()
# Send a message to Sentry reporting the failed command.
sentry_trap_err () {
  sentry_exception "Bash exit" "Error on line ${LINENO}: ${BASH_COMMAND}" "error"
}


# sentry_exception(title, message, severity)
# https://develop.sentry.dev/sdk/data-model/event-payloads/exception/
sentry_exception() {
  true
}


# sentry_event(message, severity)
# Report an event to Sentry. The message is mandatory, and the severity
# is optional. Severity can be: fatal, error, warning, info, and debug
sentry_event () {
  [ -z "${1}" ] && return 1
  message=$1
  severity=$2
  curl_opts=''

  # The Sentry server expects an API key and a project number
  if [ -z "${_SENTRY_KEY}" ] || [ -z "${_SENTRY_PROJECT}" ]; then
    echo "Error: Sentry key or project missing. Run sentry_init() first."
    return 1
  fi
  event_id=$(tr -cd 'a-f0-9' < /dev/urandom | head -c 32)
  event_timestamp=$(date --utc +"%Y-%m-%dT%H:%M:%SZ")

  # The default value for level/severity is 'info'
  if [ -z "${severity}" ] ; then
    severity='info'
  fi

  # Define variable _SENTRY_NO_CERTIFICATE_CHECK to ignore the
  # server's TLS certificate.
  if [ -n "${_SENTRY_NO_CERTIFICATE_CHECK+1}" ] ; then
    curl_opts=--insecure
  fi

  envelope='{
    "event_id": "'"$event_id"'"
  }'

  # The message must not have whitespace, or Sentry will reject it
  item='{
    "event_id": "'"$event_id"'",
    "platform": "native",
    "logentry": {
      "message": "'"$message"'"
    },
    "timestamp": "'"$event_timestamp"'",
    "server_name": "'"${HOSTNAME}"'",
    "environment": "production",
    "level": "'"$severity"'",
    "contexts": {
      "device": {
        "type": "device",
        "arch": "'"$(uname --machine)"'"
      },
      "os": {
        "type": "os",
        "name": "'"$(uname)"'",
        "version": "'"$(uname --kernel-release)"'",
        "kernel_version": "'"$(uname --kernel-version)"'"
      }
    },
    "extra": {
      "environ": '$(jc --raw printenv)'
    },
    "sdk": {
      "name": "sentry-bash",
      "version": "0.2"
    }
  }'

  # Count the length of the item variable. Do not include whitespace,
  # so {#item} won't work here. Count characters with wc and reduce by 
  # one to ignore the trailing newline.
  length=$(echo "${item}" | jq --compact-output | wc --chars)
  ((length--))

  payload="{
    \"type\": \"event\",
    \"length\": $length
  }"
  # https://develop.sentry.dev/sdk/data-model/event-payloads/

  # Format data for Sentry's envelope. Concatenate envelope payload and
  # item while preserving whitespace and newline.
  data=$(cat <<EOF
$(echo "${envelope}" | jq --compact-output)
$(echo "${payload}" | jq --compact-output)
$(echo "${item}" | jq --compact-output)
EOF
)

  # Check for valid JSON format
  if (( "${length}" > 0 )) ; then

    # Contact Sentry API and submit the message
    curl --silent --json "$data" \
      $curl_opts \
      --header "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$_SENTRY_KEY, sentry_client=zenithal-bash/0.2" \
      https://"$_SENTRY_HOST"/api/"$_SENTRY_PROJECT"/envelope/
  else
    echo "Error: Invalid JSON format"
  fi
}
