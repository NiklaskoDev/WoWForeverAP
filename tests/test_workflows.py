"""Pins the GITHUB_TOKEN scopes of the security workflow so the secret scan keeps working on pull requests."""
import yaml
from conftest import REPO_ROOT

SECURITY_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "security.yml"


def _load_security_workflow():
    return yaml.safe_load(SECURITY_WORKFLOW.read_text(encoding="utf-8"))


def test_secrets_job_permissions_are_least_privilege():
    # gitleaks-action lists the PR's commits on pull_request events, which needs pull-requests: read.
    # Job-level permissions replace the workflow-level block, so contents: read is repeated.
    workflow = _load_security_workflow()
    assert workflow["jobs"]["secrets"].get("permissions") == {"contents": "read", "pull-requests": "read"}


def test_security_workflow_default_permissions_stay_read_only_contents():
    workflow = _load_security_workflow()
    assert workflow.get("permissions") == {"contents": "read"}
