"""Pins workflow permissions and structure: the secret scan keeps working on pull requests, and only the release
publish job can write."""
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


RELEASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release.yml"
CI_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "ci.yml"
CI_SCRIPT = REPO_ROOT / "scripts" / "ci.sh"
TAG_PATTERNS = ["v[0-9]+.[0-9]+.[0-9]+", "v[0-9]+.[0-9]+.[0-9]+-pr[0-9]+"]


def _load_release_workflow():
    return yaml.safe_load(RELEASE_WORKFLOW.read_text(encoding="utf-8"))


def _step_texts(job):
    return [f"{step.get('run', '')} {step.get('uses', '')}" for step in job.get("steps", [])]


def test_release_triggers_are_version_tags_and_manual_dry_run():
    triggers = _load_release_workflow()[True]  # PyYAML reads the key `on` as boolean True
    assert set(triggers) == {"push", "workflow_dispatch"}
    assert triggers["push"]["tags"] == TAG_PATTERNS
    assert "branches" not in triggers["push"]


def test_release_permissions_are_read_only_except_publish():
    workflow = _load_release_workflow()
    assert workflow["permissions"] == {"contents": "read"}
    assert workflow["jobs"]["build"]["permissions"] == {"contents": "read"}
    assert workflow["jobs"]["publish"]["permissions"] == {"contents": "write"}


def test_release_job_chain_is_test_build_publish():
    jobs = _load_release_workflow()["jobs"]
    assert set(jobs) == {"test", "build", "publish"}
    assert jobs["test"]["uses"] == "./.github/workflows/ci.yml"
    assert jobs["build"]["needs"] == "test"
    assert jobs["publish"]["needs"] == "build"


def test_publish_only_runs_for_pushed_tags_and_runs_no_repository_code():
    publish = _load_release_workflow()["jobs"]["publish"]
    assert "github.event_name == 'push'" in publish["if"]
    assert not any("actions/checkout" in text for text in _step_texts(publish))
    assert not any("python" in step.get("run", "") for step in publish["steps"])


def test_release_builds_with_the_same_command_as_ci():
    build_steps = _load_release_workflow()["jobs"]["build"]["steps"]
    build_commands = [step for step in build_steps if step.get("run", "").strip() == "python tools/build.py"]
    assert len(build_commands) == 1
    assert "python tools/build.py" in CI_SCRIPT.read_text(encoding="utf-8")


def test_build_steps_run_in_order():
    names = [step.get("name") for step in _load_release_workflow()["jobs"]["build"]["steps"]]
    ordered = ["Check tag against VERSION", "Build", "Verify artifacts", "Release notes", "Upload release files"]
    assert all(name in names for name in ordered)
    assert [names.index(name) for name in ordered] == sorted(names.index(name) for name in ordered)


def test_publish_attaches_the_built_files_to_a_verified_tag():
    run = "\n".join(step.get("run", "") for step in _load_release_workflow()["jobs"]["publish"]["steps"])
    for expected in ("gh release create", "--verify-tag", "release/wow_forever.apworld",
                     "release/WoWForeverAP-$VERSION.zip", "release/SHA256SUMS"):
        assert expected in run


def test_release_has_no_docker_step():
    for job in _load_release_workflow()["jobs"].values():
        assert not any("docker" in text.lower() for text in _step_texts(job))


def test_ci_stays_callable_from_the_release_workflow():
    assert "workflow_call" in yaml.safe_load(CI_WORKFLOW.read_text(encoding="utf-8"))[True]
