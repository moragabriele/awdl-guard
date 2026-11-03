#!/usr/bin/env python3
"""Generates the ProfileManifests manifest (iMazing Profile Editor, ProfileCreator) from
jamf-schema.json, so both describe the same keys.

    python3 profiles/make-manifest.py
"""
import datetime
import json
import plistlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOMAIN = "io.github.moragabriele.awdlguard"
REPO = "https://github.com/moragabriele/awdl-guard"


def payload_keys():
    """Standard payload keys every ProfileManifests application manifest starts with."""
    return [
        {"pfm_name": "PayloadDescription", "pfm_title": "Payload Description", "pfm_type": "string",
         "pfm_default": "Configures AWDL Guard",
         "pfm_description": "The human-readable description of this payload."},
        {"pfm_name": "PayloadDisplayName", "pfm_title": "Payload Display Name", "pfm_type": "string",
         "pfm_default": "AWDL Guard", "pfm_require": "always",
         "pfm_description": "The human-readable name for the profile payload."},
        {"pfm_name": "PayloadIdentifier", "pfm_title": "Payload Identifier", "pfm_type": "string",
         "pfm_default": DOMAIN, "pfm_require": "always",
         "pfm_description": "The reverse-DNS-style identifier for the payload."},
        {"pfm_name": "PayloadType", "pfm_title": "Payload Type", "pfm_type": "string",
         "pfm_default": DOMAIN, "pfm_require": "always",
         "pfm_description": "The payload type."},
        {"pfm_name": "PayloadUUID", "pfm_title": "Payload UUID", "pfm_type": "string",
         "pfm_require": "always",
         "pfm_format": "^[0-9A-Za-z]{8}-[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]{12}$",
         "pfm_description": "The globally unique identifier for the payload."},
        {"pfm_name": "PayloadVersion", "pfm_title": "Payload Version", "pfm_type": "integer",
         "pfm_default": 1, "pfm_range_list": [1], "pfm_require": "always",
         "pfm_description": "The version of this specific payload."},
        {"pfm_name": "PayloadOrganization", "pfm_title": "Payload Organization", "pfm_type": "string",
         "pfm_description": "The name of the organization that provides the profile."},
    ]


def subkey(name, schema):
    """Converts one JSON-schema property to a manifest subkey."""
    key = {"pfm_type": {"object": "dictionary"}.get(schema["type"], schema["type"])}
    if name:
        key["pfm_name"] = name
    if "title" in schema:
        key["pfm_title"] = schema["title"]
    if "description" in schema:
        key["pfm_description"] = schema["description"]
    if "default" in schema:
        key["pfm_default"] = schema["default"]
    if "enum" in schema:
        key["pfm_range_list"] = schema["enum"]
        titles = schema.get("options", {}).get("enum_titles")
        if titles:
            key["pfm_range_list_titles"] = titles
    if "minimum" in schema:
        key["pfm_range_min"] = schema["minimum"]
    if "maximum" in schema:
        key["pfm_range_max"] = schema["maximum"]
    if "pattern" in schema:
        key["pfm_format"] = schema["pattern"]
    if schema["type"] == "array":
        key["pfm_subkeys"] = [subkey(None, schema["items"])]
    if schema["type"] == "object":
        required = set(schema.get("required", []))
        key["pfm_subkeys"] = []
        for child, child_schema in schema["properties"].items():
            sub = subkey(child, child_schema)
            if child in required:
                sub["pfm_require"] = "always"
            key["pfm_subkeys"].append(sub)
    return key


def main():
    schema = json.loads((HERE / "jamf-schema.json").read_text())
    properties = sorted(schema["properties"].items(), key=lambda kv: kv[1].get("property_order", 999))
    manifest = {
        "pfm_app_url": f"{REPO}/releases",
        "pfm_description": "Holds AWDL (AirDrop, AirPlay, Sidecar) down when it hurts Wi-Fi latency.",
        "pfm_documentation_url": f"{REPO}#configuration",
        "pfm_domain": DOMAIN,
        "pfm_format_version": 1,
        "pfm_last_modified": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0, tzinfo=None),
        "pfm_platforms": ["macOS"],
        # The daemon reads system-wide managed preferences only.
        "pfm_targets": ["system"],
        "pfm_title": "AWDL Guard",
        "pfm_unique": True,
        "pfm_version": 1,
        "pfm_subkeys": payload_keys() + [subkey(name, prop) for name, prop in properties],
    }
    out = HERE / f"{DOMAIN}.plist"
    with out.open("wb") as f:
        plistlib.dump(manifest, f, sort_keys=True)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
