#!/usr/bin/env bash

########################################################################
 # Copyright (c) Intel Corporation 2023
 # SPDX-License-Identifier: BSD-3-Clause
########################################################################


# Note: inspiration and work in this file is derived from https://github.com/deviantony/docker-elk.
# This repo acts as a springboard for others to setup the ELK stack.
# The code has been modified to remove the Logstash dependency to remove the need for JVM to be installed.

set -eu
set -o pipefail

echo "Running setup script..."

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --------------------------------------------------------
# Users declarations

declare -A users_passwords
users_passwords=(
	[kibana_system]="${KIBANA_SYSTEM_PASSWORD:-}"
)

echo "-------- $(date) --------"

state_file="$(dirname "${BASH_SOURCE[0]}")/state/.done"
#if [[ -e "$state_file" ]]; then
#	log "State file exists at '${state_file}', skipping setup"
#	exit 0
#fi

log 'Waiting for availability of Elasticsearch. This can take several minutes.'

declare -i exit_code=0
wait_for_elasticsearch || exit_code=$?

if ((exit_code)); then
	case $exit_code in
		6)
			suberr 'Could not resolve host. Is Elasticsearch running?'
			;;
		7)
			suberr 'Failed to connect to host. Is Elasticsearch healthy?'
			;;
		28)
			suberr 'Timeout connecting to host. Is Elasticsearch healthy?'
			;;
		*)
			suberr "Connection to Elasticsearch failed. Exit code: ${exit_code}"
			;;
	esac

	exit $exit_code
fi

sublog 'Elasticsearch is running'

for role in "${!roles_files[@]}"; do
	log "Role '$role'"

	declare body_file
	body_file="$(dirname "${BASH_SOURCE[0]}")/roles/${roles_files[$role]:-}"
	if [[ ! -f "${body_file:-}" ]]; then
		sublog "No role body found at '${body_file}', skipping"
		continue
	fi

	sublog 'Creating/updating'
	ensure_role "$role" "$(<"${body_file}")"
done

for user in "${!users_passwords[@]}"; do
	log "User '$user'"
	if [[ -z "${users_passwords[$user]:-}" ]]; then
		sublog 'No password defined, skipping'
		continue
	fi

	declare -i user_exists=0
	user_exists="$(check_user_exists "$user")"

	if ((user_exists)); then
		sublog 'User exists, setting password'
		set_user_password "$user" "${users_passwords[$user]}"
	else
		if [[ -z "${users_roles[$user]:-}" ]]; then
			err '  No role defined, skipping creation'
			continue
		fi

		sublog 'User does not exist, creating'
		create_user "$user" "${users_passwords[$user]}" "${users_roles[$user]}"
	fi
done

mkdir -p "$(dirname "${state_file}")"
touch "$state_file"