"""Classify image-only changes before jobs receive AWS credentials."""
import argparse
import re
import subprocess

IMAGE_FILE = "envs/dev/platform-image.auto.tfvars"


def image_only(paths):
    return paths == [IMAGE_FILE]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("head")
    parser.add_argument("--pull-request", action="store_true")
    args = parser.parse_args()
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (args.base, args.head)):
        raise SystemExit("Expected full Git commit IDs")
    if args.base == "0" * 40:
        print("image_only=false")
        return
    revisions = [args.base + "..." + args.head] if args.pull_request else [args.base, args.head]
    result = subprocess.run(
        ["git", "diff", "--name-only", "-z", *revisions],
        capture_output=True, text=True, check=True,
    )
    paths = [path for path in result.stdout.split("\0") if path]
    print("image_only=" + str(image_only(paths)).lower())


if __name__ == "__main__":
    main()
