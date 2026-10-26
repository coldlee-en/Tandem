#!/usr/bin/env python3
"""Publish this project and dispatch its Pages and native IPA workflows.

Uses the current gh account. It does not prompt for or store credentials.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent

def command(arguments, *, input_text=None, allow_failure=False):
    result = subprocess.run(arguments, cwd=ROOT, input=input_text, text=True, capture_output=True)
    if result.returncode and not allow_failure:
        raise RuntimeError((result.stderr or result.stdout).strip() or f"Command failed: {arguments[0]}")
    return result

def api(path, *, method="GET", body=None):
    arguments = ["gh", "api", "--hostname", "github.com", "--method", method, path]
    if body is not None:
        arguments += ["--input", "-"]
    result = command(arguments, input_text=json.dumps(body) if body is not None else None)
    return json.loads(result.stdout) if result.stdout.strip() else None

def dispatch(repository, workflow, inputs=None):
    # A new repository's workflow definitions can take a few seconds to index.
    for attempt in range(6):
        try:
            api(f"repos/{repository}/actions/workflows/{workflow}/dispatches", method="POST",
                body={"ref": "main", "inputs": inputs or {}})
            return
        except RuntimeError as error:
            if attempt == 5 or "404" not in str(error):
                raise
            time.sleep(2)

def publish(name):
    # Authentication is checked before any local or remote mutation.
    try:
        account = api("user")
    except RuntimeError as error:
        raise RuntimeError("GitHub authentication is unavailable. Connect the GitHub account or authenticate gh, then rerun. " + str(error)) from error
    owner = account["login"]
    repository = f"{owner}/{name}"
    metadata = ROOT / ".git/tandem-publication.json"
    if not (ROOT / ".git").exists():
        command(["git", "init", "-b", "main"])
    elif not (ROOT / ".git").is_dir():
        raise RuntimeError("Use the standalone project checkout, not a linked worktree.")
    branch = command(["git", "symbolic-ref", "--short", "HEAD"]).stdout.strip()
    if branch != "main":
        raise RuntimeError("Publication expects the project on its main branch; existing branches are preserved.")
    if metadata.is_file():
        saved = json.loads(metadata.read_text())
        if saved.get("repository") != repository:
            raise RuntimeError("This checkout records a different publication repository; no remote was changed.")
        remote = api(f"repos/{repository}")
    else:
        existing_origin = command(["git", "remote", "get-url", "origin"], allow_failure=True)
        if existing_origin.returncode == 0:
            raise RuntimeError("This checkout already has an origin; no existing repository was changed.")
        try:
            remote = api("user/repos", method="POST", body={
                "name": name,
                "description": "Tandem: experimental native iOS 3DS and Switch emulator integration",
                "private": False,
                "has_issues": True,
                "auto_init": False,
            })
        except RuntimeError as error:
            if "403" in str(error):
                raise RuntimeError(f"Authenticated as {owner}, but GitHub denied creation of {repository}. The connection needs repository-creation/administration access. No repository was created. " + str(error)) from error
            raise
        metadata.write_text(json.dumps({"repository": repository, "url": remote["html_url"]}, indent=2) + "\n")
    existing_origin = command(["git", "remote", "get-url", "origin"], allow_failure=True)
    if existing_origin.returncode:
        command(["git", "remote", "add", "origin", remote["clone_url"]])
    elif existing_origin.stdout.strip() != remote["clone_url"]:
        raise RuntimeError("The checkout's origin differs from the recorded repository; publication stopped.")
    command(["git", "add", "--all"])
    changed = command(["git", "diff", "--cached", "--quiet"], allow_failure=True)
    if changed.returncode == 1:
        author = account.get("name") or owner
        email = f"{account['id']}+{owner}@users.noreply.github.com"
        command(["git", "-c", f"user.name={author}", "-c", f"user.email={email}",
                 "commit", "-m", "Add Tandem iOS project, IPA build workflow, and project website"])
    elif changed.returncode:
        raise RuntimeError(changed.stderr.strip() or "Unable to review staged changes.")
    # The credential helper supplies credentials directly to git without printing
    # them, writing a token to a file, or changing the user's global Git config.
    command(["git", "-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential",
             "push", "--set-upstream", "origin", "main"])
    api(f"repos/{repository}", method="PATCH", body={"default_branch": "main"})
    pages_path = f"repos/{repository}/pages"
    try:
        pages = api(pages_path, method="POST", body={"build_type": "workflow"})
    except RuntimeError as error:
        if "409" not in str(error):
            raise
        pages = api(pages_path, method="PUT", body={"build_type": "workflow"})
    if isinstance(pages, dict) and pages.get("html_url"):
        api(f"repos/{repository}", method="PATCH", body={"homepage": pages["html_url"]})
    dispatch(repository, "pages.yml")
    dispatch(repository, "build-ipa.yml", {"mode": "native"})
    state = {
        "repository": repository,
        "repositoryUrl": remote["html_url"],
        "pagesConfiguredUrl": pages.get("html_url") if isinstance(pages, dict) else None,
        "pagesDeployment": "dispatched; success not yet verified",
        "nativeIpaBuild": "dispatched; artifact not yet built",
        "actionsUrl": remote["html_url"] + "/actions",
    }
    metadata.write_text(json.dumps(state, indent=2) + "\n")
    print(json.dumps(state, indent=2))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", default="tandem-ios", help="New public project repository name")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,99}", args.name) or args.name.lower().endswith(".github.io"):
        parser.error("Choose a project repository name, not a GitHub profile website repository.")
    try:
        publish(args.name)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
