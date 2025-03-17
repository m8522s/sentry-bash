#!/bin/bash

# Use Sentry.io for error reporting:
#   source /usr/lib64/sentry_sdk.sh
#   sentry_init 83105fca2e2e2351b01 4508410146651  (sentry.io)
#   sentry_init 8f7152da911 1 bugsink.example.net  (bugsink)
#   sentry_breadcrumb "mutex 11Ti08"
#   sentry_event "failed to read mutex" "error"
#   sentry_message "Exception" "failed to read mutex" "error"


# Load JSON library
if ! source /usr/lib64/jshn.sh ; then
  echo "JSON library missing. Install with:"
  echo "wget --output-document=/usr/lib64/jshn.sh https://raw.githubusercontent.com/jeganathgt/libjson-sh/refs/heads/dev/include/jshn.sh"
fi

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
  #title=$1
  message=$2
  severity=$3

  # Workaround: relay to sentry_event
  sentry_event "${message}" "${severity}"
}


# sentry_breadcrumb(message, category)
# Enright the next message/event with additional information (breadcrumbs).
# Message is mandatory, category is optional and defaults to 'log'.
sentry_breadcrumb() {
  message=$1
  category=$2

  # The default category is 'log'
  if [ -z "${category}" ] ; then
    category='log'
  fi

  # First call to this function? The JSON object does not exists yet
  if [ -z "${JSON_CURSOR}" ] ; then
    json_init "object"
    json_add_object "breadcrumbs"
    json_add_array "values"
  fi

  json_add_object
  json_add_string "timestamp" "$(date --utc +'%Y-%m-%dT%H:%M:%SZ')"
  json_add_string "message" "${message}"
  json_add_string "category" "${category}"
  json_close_object
}


_sentry_environment_variables() {
  # Initialize JSON object
  json_init "object"
  json_add_object "environ"

  for envvar in $(compgen -e) ; do
    if    [ "${envvar:0:5}" == "JSON_" ] || [ "${envvar:0:5}" == "KEYS_" ] \
       || [ "${envvar:0:5}" == "TYPE_" ] || [ "${envvar:0:5}" == "BASH_" ] \
       || [ "${envvar:0:4}" == "KEY_" ]  || [ "${envvar:0:6}" == "VALUE_" ] \
       || [ "$envvar" == "LS_COLORS" ] ; then
      continue
    else
      json_add_string "$envvar" "${!envvar}"
    fi
  done

  json_close_object
  json_close_array
  json_env=$(json_dump)
  json_cleanup
  echo "${json_env}"
}


# sentry_message(title, message, severity)
# Relay to sentry_event().
sentry_message () {
  title=$1
  message=$2
  severity=$3
  sentry_event "${message}" "${severity}"
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

  # Find the Git hash
  if git rev-parse HEAD 2>/dev/null ; then
    revision="Git hash: $(git rev-parse HEAD)"
  else
    revision='unknown'
  fi

  # Define variable _SENTRY_NO_CERTIFICATE_CHECK to ignore the
  # server's TLS certificate.
  if [ -n "${_SENTRY_NO_CERTIFICATE_CHECK+1}" ] ; then
    curl_opts=--insecure
  fi

  # Breadcrumbs
  # https://develop.sentry.dev/sdk/data-model/event-payloads/breadcrumbs/
  breadcrumbs=$(json_dump)
  json_cleanup
  if [ -n "${breadcrumbs}" ] ; then
    # The breadcumbs will join the $item variable, so the JSON construct must
    # loose the outer brackets and append a comma.
    breadcrumbs="${breadcrumbs:1:${#breadcrumbs}-2}"
    breadcrumbs+=','
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
    '$breadcrumbs'
    "extra": '$(_sentry_environment_variables)',
    "release": "'"$revision"'",
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
    curl --silent --data "$data" \
      $curl_opts \
      --header "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$_SENTRY_KEY, sentry_client=zenithal-bash/0.2" \
      https://"$_SENTRY_HOST"/api/"$_SENTRY_PROJECT"/envelope/
  else
    echo "Error: Invalid JSON format"
  fi
}
