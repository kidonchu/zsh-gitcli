#!/usr/bin/env bats

load ../test_helper
load ../../src/utils/stash

function setup() {
	_setup_git
	_cd_git
}

function teardown() {
	cd ..
	_teardown_git
}

@test "stashing no change" {
	run save_stash
	[ "$status" -eq 0 ]
}

@test "stashing added file" {
	touch b.txt
	run save_stash
	[ "$status" -eq 0 ]

	run git status -s
	[ -z "$output" ]
}

@test "stashing modified file" {
	echo "text change" >> a.txt
	run save_stash
	[ "$status" -eq 0 ]

	run git status -s
	[ -z "$output" ]
}

@test "stashing deleted file" {
	rm -f a.txt
	run save_stash
	[ "$status" -eq 0 ]

	run git status -s
	[ -z "$output" ]
}

@test "saving stashed hash in current branch's config" {
	echo "text change" >> a.txt
	run save_stash

	run git config branch.feature/test-branch.laststash
	[ "$status" -eq 0 ]
	[[ "$output" =~ [[:alnum:]]{40} ]]
}

@test "popping stash, laststash not set" {
	run pop_stash "feature/test-branch"
	[ "$status" -eq 0 ]
}

@test "popping stash, laststash set but empty" {
	run git config branch.feature/test-branch.laststash ""
	run pop_stash "feature/test-branch"
	[ "$status" -eq 0 ]
}

@test "popping stash, no saved stash" {
	run git config branch.feature/test-branch.laststash "2007a3809d53b20b0e701eeff36c4090175ee644"
	run pop_stash "feature/test-branch"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "unable to get a list of stashes" ]]
}

@test "popping stash, laststash set but non-existent" {
	echo "text change 1" >> a.txt
	run git stash
	run git config branch.feature/test-branch.laststash "2007a3809d53b20b0e701eeff36c4090175ee644"

	run pop_stash "feature/test-branch"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "unable to find a stash" ]]
}

@test "popping stash, laststash set and existent" {
	echo "text change 1" >> a.txt
	run git stash
	run git reflog show stash --pretty=format:%H -n 1
	stashHash="$output"

	run git config branch.feature/test-branch.laststash "$stashHash"

	# test laststash set to corrent hash
	run pop_stash "feature/test-branch"
	[ "$status" -eq 0 ]

	run git status -s
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^[[:space:]]*M.*a\.txt ]]
}