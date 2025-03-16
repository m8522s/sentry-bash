# Inofficial Sentry SDK for Bash

Welcome to the inofficial Bash SDK for **[Sentry](http://sentry.io/)**!

## Getting Started

### Installation

```bash
git clone https://github.com/m8522s/sentry-bash.git
mv sentry-bash/sentry_sdk.sh /usr/lib64/
rm -rf sentry-bash/
```


### Basic Configuration

Load the Sentry library and initialize with your personal key and the project number.

```bash
source /usr/lib64/sentry_sdk.sh
sentry_init 83105fca2e2e2351b1 450841014661
```


### Quick Usage Example

Generate a message that will show up in Sentry.

```bash
sentry_event "Oops, something went wrong!" "error"
```
