function _gitcli_get_config() {
	config=`git config --list | grep "${1}"`
	if [ -z "${config}" ]; then
		return 0
	fi
	config=`echo ${config} | cut -d'=' -f 2`
	echo "${config}"
}

function _gitcli_current_branch() {
	branch=`git branch | grep \* | cut -d ' ' -f2`
	echo "${branch}"
}

function _gitcli_create() {

	_gitcli_process "Preparing to create new branch ${newBranch} from ${srcBranch}"

	newBranch=${1}
	srcBranch=${2}

	# first, check if we already have a branch with same name
	if [[ ! -z `git branch --list ${1}` ]]; then
		_gitcli_notice "Branch ${newBranch} already exists"
		return 0
	fi

	_gitcli_fetch_by_branch "${srcBranch}"

	_gitcli_process "Creating new branch ${newBranch} from ${srcBranch}"

	git branch "${newBranch}" ${srcBranch}
}

function _gitcli_checkout() {

	fromBranch=`_gitcli_current_branch`
	toBranch=${1}

	_gitcli_process "${fromBranch} => ${toBranch}"

	# check to see if there are things to be stashed
	hasChanges=`git status -s`
	if [[ ! -z "${hasChanges}" ]]; then
		_gitcli_process "Stashing changes"
		# if has something to stash, stash them and store the commit in config
		git add -A
		git stash
		sha=`git reflog show stash --pretty=format:%H | head -1`
		git config "branch.${fromBranch}.laststash" "${sha}"
	fi

	# store fromBranch as recent branch now and checkout toBranch
	_gitcli_process "Checking out ${toBranch}"
	git config story.mostrecent "${fromBranch}"
	git checkout ${toBranch}

	# if there is last stash for the switched branch, pop that out
	laststash=`_gitcli_get_config "branch.${toBranch}.laststash"`
	if [[ ! -z "${laststash}" ]]; then

		_gitcli_process "Preparing to pop out last stash"

		stashIndex=0
		stashes=`git reflog show stash --pretty=format:%H`
		for stash in ${stashes}; do
			if [[ ${stash} == ${laststash} ]]; then
				break
			fi
			((stashIndex++))
		done

		_gitcli_process "Popping out stash@{${stashIndex}}"

		git stash pop "stash@{${stashIndex}}"
		git config "branch.${toBranch}.laststash" ""
	fi
}

function _gitcli_pull() {

	fromBranch=${1}

	_gitcli_process "Preparing to pull from ${fromBranch}"

	# check to see if there are things to be stashed
	hasChanges=`git status -s`
	if [[ ! -z "${hasChanges}" ]]; then
		_gitcli_error "You have changes. Resolve them first"
		exit 1
	fi

	_gitcli_fetch_all

	_gitcli_process "Pulling from ${fromBranch}"

	remote=`echo ${fromBranch} | cut -d'/' -f 1`
	branch=`echo ${fromBranch} | cut -d'/' -f 2`

	git pull "${remote}" "${branch}"
}

function _gitcli_copy_issue_to_clipboard() {

	branch=`_gitcli_current_branch`
	pattern='^(feature|bugfix)/([0-9]+)(-.*)?'

	if [[ "$branch" =~ $pattern ]]; then
		# if issue id exists in the branch name, copy to clipboard
		issueId=${BASH_REMATCH[2]}
		echo `printf "[DEVJIRA-%s]" ${issueId}` | pbcopy
	else
		_gitcli_notice "Unable to extract issue id from ${branch}"
	fi
}

function _gitcli_open_pr_url() {

	base="${1}"

	_gitcli_process "Preparing to open Pull Request URL with base ${base}"

	# prepare base information
	baseRemote=`echo ${base} | cut -d'/' -f 1`
	baseBranch=`echo ${base} | cut -d'/' -f 2`
	baseUri=`_gitcli_get_config "remote.${baseRemote}.url" | sed 's/git@github.com://' | sed 's/\.git//'`
	baseOwner=`echo ${baseUri} | cut -d'/' -f 1`
	baseRepo=`echo ${baseUri} | cut -d'/' -f 2`

	#prepare head information
	headBranch=`_gitcli_current_branch`
	headRemote=`_gitcli_get_config "branch.${headBranch}.remote"`
	headUri=`_gitcli_get_config "remote.${headRemote}.url" | sed 's/git@github.com://' | sed 's/\.git//'`
	headOwner=`echo ${headUri} | cut -d'/' -f 1`
	headRepo=`echo ${headUri} | cut -d'/' -f 2`

	url=`printf "https://github.com/%s/%s/compare/%s...%s:%s?expand=1" \
		"${baseOwner}" "${baseRepo}" "${baseBranch}" "${headOwner}" "${headBranch}"`

	_gitcli_process "Opening Pull Request URL with base ${base}"

	open "${url}"
}

function _gitcli_fetch_all() {
	_gitcli_process "Fetching all remotes"
	git fetch --all
}

function _gitcli_fetch_by_branch() {
	srcBranch="${1}"

	if [[ "${srcBranch}" =~ ([-a-zA-Z0-9]+)/.* ]]; then
		remote=${BASH_REMATCH[1]}
		_gitcli_process "Fetching most recent changes from ${remote}"
		git fetch "${remote}"
	else
		_gitcli_process "Fetching most recent changes"
		git fetch
	fi
}

function _gitcli_create_pr() {

	token=`_gitcli_get_config "story.oauthtoken"`
	if [[ -z "${token}" ]]; then
		_gitcli_error "Missing oauth token. Add one using `git config story.oauthtoken <token>`"
		exit 1
	fi

	# prepare headers
	headers=()
	headers+=("Authorization: token ${token}")
	headers+=("Accept: application/vnd.github.polaris-preview+json")
	headers+=("Content-Type: application/json")

	cmd="curl -X POST"
	for header in "${headers[@]}"; do
		cmd="${cmd} -H '${header}'"
	done

	echo "cmd:" $cmd

	title="Title"
	body="Body"
	head="kidonchu:test/feature3"
	base="master"

	title=`cat ./.git/PR_BODY_MESSAGE.md`

	body=`echo "<?php echo json_encode(array('title' => '${title}')); ?>" | php`

	owner="kidonchu"
	repo="test-repo"
	url=`sprinf "https://api.github.com/repos/%s/%s/pulls" "${owner}" "${repo}"`
	curl -i -X POST -H 'Authorization: token ' -H 'Content-Type: application/json' -H 'Accept: application/vnd.github.polaris-preview+json' -d '{"title": "Title","base":"master","head":"feature/test3"}' https://api.github.com/repos/kidonchu/test-repo/pulls

	echo "url:" $url
}

function _gitcli_find_src_branch() {

	src=${1}

	srcBranch=`_gitcli_get_config "story.source.${src}"`
	if [[ -z "${srcBranch}" ]]; then
		_gitcli_error "Unable to find source branch with ${src}"
		exit 1
	fi

	echo "${srcBranch}"
}

function _gitcli_choose_one() {

	choices=${1}

	PS3=">>> Choose one: "
	select choice in "${choices[@]}"
	do
		case ${choice} in
			*)
				echo ${choice}
				break
				;;
		esac
	done
}