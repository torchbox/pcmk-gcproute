#! /bin/sh
# vim:set sw=8 ts=8 noet:
#
# Copyright (c) 2016-2017 Torchbox Ltd.
#
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely. This software is provided 'as-is', without any express or implied
# warranty.
#
# Manage Google Cloud Platform (GCP) routing table entries as OCF resources.
#
# paramaters:
#
#	name: 		(required) route name
#	network:	(required) GCP network to create route in
#	prefix:		(required) route network
#	prefix_length:	(required) route prefix length (/32 for a single address)
#	gcloud_bin:	(optional) path to the 'gcloud' binary (default: 'gcloud')
#
# The route is always added with the current host as the gateway.
#

: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs

GCLOUD="${OCF_RESKEY_gcloud_bin:-gcloud} -q"

metadata() {
	cat <<DECK
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="gcproute">
	<version>1.0</version>
	<longdesc lang="en">
		Manage Google Cloud Platform routes.
	</longdesc>
	<shortdesc lang="en">Manage Google Cloud Platform routes</shortdesc>

	<parameters>
		<parameter name="name" unique="1" required="1">
			<longdesc lang="en">The name of the route.</longdesc>
			<shortdesc lang="en">Route name</shortdesc>
			<content type="string" default="" />
		</parameter>

		<parameter name="network" unique="1" required="1">
			<longdesc lang="en">GCP network in which the route should be created.</longdesc>
			<shortdesc lang="en">Network name</shortdesc>
			<content type="string" default="" />
		</parameter>

		<parameter name="prefix" unique="1" required="1">
			<longdesc lang="en">Network prefix of the route.</longdesc>
			<shortdesc lang="en">Network prefix</shortdesc>
			<content type="string" default="" />
		</parameter>

		<parameter name="prefix_length" unique="1" required="1">
			<longdesc lang="en">Prefix length of the route.</longdesc>
			<shortdesc lang="en">Prefix length</shortdesc>
			<content type="string" default="" />
		</parameter>

		<parameter name="gcloud_bin" unique="1" required="0">
			<longdesc lang="en">Path to the gcloud binary.</longdesc>
			<shortdesc lang="en">gcloud path</shortdesc>
			<content type="string" default="gcloud" />
		</parameter>
	</parameters>

	<actions>
		<action name="start" timeout="20s" />
		<action name="stop" timeout="20s" />
		<action name="monitor" depth="0" timeout="20s" interval="5s" />
		<action name="validate-all" timeout="20s" />
		<action name="meta-data" timeout="5s" />
	</actions>
</resource-agent>
DECK
	return $OCF_SUCCESS
}

usage() {
	echo >&2 "usage: $0 <start|stop|status|monitor|validate-all|meta-data>"
}

if [ $# -ne 1 ]; then
	usage $OCF_ERR_ARGS
fi

get_instance_url() {
	project=$(curl -sH'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
	instance_name=$(curl -sH'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name)
	zone=$(curl -sH'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4)

	echo "https://www.googleapis.com/compute/v1/projects/${project}/zones/${zone}/instances/${instance_name}"
}

get_zone() {
	curl -sH'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4
}

get_instance_name() {
	curl -sH'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name
}

route_exists() {
	$GCLOUD compute routes describe $OCF_RESKEY_name >/dev/null 2>&1 || return 1
	return 0
}

get_route_instance() {
	T=$(mktemp /tmp/gcproute.XXXXXX)
	$GCLOUD compute routes describe $OCF_RESKEY_name >$T 2>&1

	if [ $? -ne 0 ]; then
		rm $T
		echo ""
		return
	fi

	awk '/nextHopInstance/ { print $2}' $T
	rm $T
}

start() {
	if monitor; then
		return
	fi

	if route_exists; then
		$GCLOUD compute routes delete $OCF_RESKEY_name
	fi

	$GCLOUD compute routes create $OCF_RESKEY_name 					\
		--network=${OCF_RESKEY_network}						\
		--destination-range=${OCF_RESKEY_prefix}/${OCF_RESKEY_prefix_length}	\
		--next-hop-instance=$(get_instance_name)				\
		--next-hop-instance-zone=$(get_zone)

	if [ $? -eq 0 ]; then
		return 0
	else
		return 1
	fi
}

stop() {
	if ! monitor; then
		return
	fi

	$GCLOUD compute routes delete $OCF_RESKEY_name
	if [ $? -eq 0 ]; then
		return 0
	else
		return 1
	fi
}

monitor() {
	if ! route_exists; then
		return 7
	fi

	instance=$(get_route_instance)
	myurl=$(get_instance_url)

	if [ "$instance" = "$myurl" ]; then
		return 0
	else
		return 7
	fi
}

validate_all() {
	[ -n "${OCF_RESKEY_name}" ] || return 2
	[ -n "${OCF_RESKEY_network}" ] || return 2
	[ -n "${OCF_RESKEY_prefix}" ] || return 2
	[ -n "${OCF_RESKEY_prefix_length}" ] || return 2
	$GCLOUD help >/dev/null 2>&1 || return 5
	return 0
}

case $1 in
	meta-data)	metadata;;
	start)		start;;
	stop)		stop;;
	monitor)	monitor;;
	validate-all)	validate_all;;
	usage)		usage; exit $OCF_SUCCESS;;
	*)		usage; exit $OCF_ERR_UNIMPLEMENTED;;
esac

exit $?
