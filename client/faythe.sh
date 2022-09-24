#!/bin/sh

# (POSIX) shell script to implement tranparently signed ssh public keys
# on a per-domain basis. Uncomment alias lines at end for simplest usage.
# Note that you can still use /usr/bin/ssh if for any reason this then
# interferes with your normal ssh

_faythe_signkey() {

	# no args, just let ssh/scp/sftp do its thing
	if [ $# -eq 0 ]; then
		return 0
	fi
 
	# read $HOME/.config/faythe/domains
	# TODO - what should happen if this doesn't exist?
	found=""
	while read domain login idfile;
	do
		if printf -- "$*" | egrep -q "\.${domain}([[:space:]]|:|\$)"; then
			found=$domain
			break
		fi
	done < $HOME/.config/faythe/domains

	if [ -z "${found}" ]; then
		# no match so no need to check private key
		return 0
	fi

	# deal with ~ expansion in idfile
	case "$idfile" in "~"*)
		idfile="${HOME}/${idfile#"~"}"
		;;
	esac
	cert="${idfile}-cert.pub"

	# if connecting to sshenrol.${domain}, just let ssh do its thing
	if printf -- "$*" | egrep -q "@?sshenrol\.${domain}([[:space:]]|$)"; then
		return 0
	fi

	# explicit renewal - remove if defined

	[ -n "${FAYTHE_RENEW:-}" ] && rm -f $cert

	if [ -f "$cert" ]; then
		valid=$( /usr/bin/ssh-keygen -Lf "$cert" | grep Valid: | sed -E 's/^(.* to )(.*)/\2/' )
		if [ $( uname ) = "Darwin" ]; then	# mac
			until=$( date -j -f '%FT%T' "$valid" +'%s' )
		else
			until=$( date -d "$valid" +'%s' )
		fi
		now=$( date +'%s' )
		if [ "$now" -lt "$until" ]; then
			[ -n "${FAYTHE_VERBOSE:-}" ] && printf "+faythe: Current signed certificate valid until ${valid}\\n" >&2
			return 0
		else
			[ -n "${FAYTHE_VERBOSE:-}" ] && printf "+faythe: Signed certificate expired ${valid}\\n" >&2
		fi
	fi

	[ -n "${FAYTHE_VERBOSE:-}" ] && printf '+faythe: Requesting signed certificate ...\n' >&2
	output=$( /usr/bin/ssh -T "${login}@sshca.${domain}" 2>/dev/null )

	if [ -z "$output" ]; then
		return 1
	fi

	key=$( printf "$output" | sed -E -n '/^ssh-(rsa|ed25519|ecdsa)-cert-v[[:digit:]]+@openssh.com AAA/p' )

	if [ ! -z "$key" ]; then
		printf "%s" "$key" > "$cert"
		valid=$( /usr/bin/ssh-keygen -Lf "$cert" | grep Valid: | sed -E 's/^(.* to )(.*)/\2/' )
		[ -n "${FAYTHE_VERBOSE:-}" ] && printf "+faythe: Wrote new key to %s file - valid until %s\\n" "$cert" "$valid" >&2
		return 0
	else
		printf '*** +faythe: Failed to update cert signed key.\n' >&2
		printf "$output"
		return 1
	fi

	return 0
}

restore_faythe() {
	FAYTHE_RENEW=1 _faythe_signkey $*
}

fssh() {
	if _faythe_signkey $*; then
		/usr/bin/ssh $*
	fi
}

fscp() {
	if _faythe_signkey $*; then
		/usr/bin/scp $*
	fi
}

fsftp() {
	if _faythe_signkey $*; then
		/usr/bin/sftp $*
	fi
}

# uncomment for most transparent setup
alias ssh=fssh
alias scp=fscp
alias sftp=fsftp
