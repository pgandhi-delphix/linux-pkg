#!/usr/bin/env bash
#
# Copyright 2021 Delphix
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# shellcheck disable=SC2034

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/dlpx-app-gate.git"
PACKAGE_DEPENDENCIES="adoptopenjdk crypt-blowfish host-jdks"

function prepare() {
	logmust read_list "$WORKDIR/repo/appliance/packaging/build-dependencies"
	logmust install_pkgs "${_RET_LIST[@]}"

	logmust install_pkgs \
		"$DEPDIR"/adoptopenjdk/*.deb \
		"$DEPDIR"/crypt-blowfish/*.deb \
		"$DEPDIR"/host-jdks/*.deb
}

function build() {
	export JAVA_HOME
	JAVA_HOME=$(cat "$DEPDIR/adoptopenjdk/JDK_PATH") ||
		die "Failed to read $DEPDIR/adoptopenjdk/JDK_PATH"

	export LANG
	LANG=en_US.UTF-8

	logmust cd "$WORKDIR/repo"

	#
	# The "appliance-build-stage0" Jenkins job consumes this file,
	# along with various other files (e.g. licensing metadata).
	# Thus, if we don't generate it here, the Jenkins job that
	# builds the appliance will fail.
	#
	# shellcheck disable=SC2016
	logmust jq -n \
		--arg h "$(git rev-parse HEAD)" \
		--arg d "$(date --utc --iso-8601=seconds)" \
		'{ "dlpx-app-gate" : { "git-hash" : $h, "date": $d }}' \
		>"$WORKDIR/artifacts/metadata.json"

	#
	# Build the virtualization package
	#
	logmust cd "$WORKDIR/repo/appliance"

	local args=()

	# Here we check for whether the environment variables are set and pass them along. We check for
	# existence instead of emptiness to avoid adding a layer of interpretation.

	# We use parameter expansion in the form of ${variable+nothing} which evaluates to the variable
	# 'nothing' if 'variable' is not set. Because 'nothing' is not defined it evaluates to "" when 'variable'
	# is not set. So [[ "" ]] is what is actually evaluated when 'variable' is not set.

	if [[ ${SECRET_DB_USE_JUMPBOX+nothing} ]]; then
		args+=("-DSECRET_DB_USE_JUMPBOX=$SECRET_DB_USE_JUMPBOX")
	fi

	if [[ ${SECRET_DB_JUMP_BOX_HOST+nothing} ]]; then
		args+=("-DSECRET_DB_JUMP_BOX_HOST=$SECRET_DB_JUMP_BOX_HOST")
	fi

	if [[ ${SECRET_DB_JUMP_BOX_USER+nothing} ]]; then
		args+=("-DSECRET_DB_JUMP_BOX_USER=$SECRET_DB_JUMP_BOX_USER")
	fi

	if [[ ${SECRET_DB_JUMP_BOX_PRIVATE_KEY+nothing} ]]; then
		if [[ ! -f "$SECRET_DB_JUMP_BOX_PRIVATE_KEY" ]]; then
			die "Jumpbox private key not found."
		fi
		args+=("-DSECRET_DB_JUMP_BOX_PRIVATE_KEY=$SECRET_DB_JUMP_BOX_PRIVATE_KEY")
	fi

	if [[ ${SECRET_DB_AWS_ENDPOINT+nothing} ]]; then
		args+=("-DSECRET_DB_AWS_ENDPOINT=$SECRET_DB_AWS_ENDPOINT")
	fi

	if [[ ${SECRET_DB_AWS_PROFILE+nothing} ]]; then
		args+=("-DSECRET_DB_AWS_PROFILE=$SECRET_DB_AWS_PROFILE")
	fi

	if [[ ${SECRET_DB_AWS_REGION+nothing} ]]; then
		args+=("-DSECRET_DB_AWS_REGION=$SECRET_DB_AWS_REGION")
	fi

	args+=("-Ddockerize=true")
	args+=("-DbuildJni=true")

	if [[ -n "$DELPHIX_RELEASE_VERSION" ]]; then
		args+=("-DhotfixGenDlpxVersion=$DELPHIX_RELEASE_VERSION")
	fi

	logmust ant "${args[@]}" all-secrets package

	#
	# Publish the virtualization package artifacts
	#
	logmust cd "$WORKDIR/repo/appliance"
	logmust rsync -av packaging/build/distributions/ "$WORKDIR/artifacts/"
	logmust rsync -av \
		bin/out/common/com.delphix.common/uem/tars \
		"$WORKDIR/artifacts/hostchecker2"
	logmust cp -v \
		server/api/build/api/json-schemas/delphix.json \
		"$WORKDIR/artifacts"
	logmust cp -v \
		dist/server/opt/delphix/client/etc/api.ini \
		"$WORKDIR/artifacts"
	logmust cp -v \
		packaging/build/reports/dependency-license/* \
		"$WORKDIR/artifacts/"

	#
	# Build the "toolkit-devkit" artifacts
	#
	logmust cd "$WORKDIR/repo/appliance/toolkit"
	if [[ -n "$DELPHIX_RELEASE_VERSION" ]]; then
		logmust ant \
			-Dversion.number="$DELPHIX_RELEASE_VERSION" \
			toolkit-devkit
	else
		logmust ant \
			"-Dversion.number=$(date --utc +%Y-%m-%d-%H-%m)" \
			toolkit-devkit
	fi

	#
	# Publish the "toolkit-devkit" artifacts
	#
	logmust cd "$WORKDIR/repo/appliance"
	logmust mkdir -p "$WORKDIR/artifacts/hostchecker2"
	logmust cp -v toolkit/toolkit-devkit.tar "$WORKDIR/artifacts"
}
