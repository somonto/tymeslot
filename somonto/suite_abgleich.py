#!/usr/bin/env python3
"""Somonto fork: compare the failures of the full upstream suite (suite.log) with
somonto/bekannte-abweichungen.txt, the upstream tests that check the old Quill flow
(message field, "Duration" step, no source link) and so fail here by design.

Exit 1 when a test fails that is not on the list (a new break, e.g. after merging an
upstream tag) or when the suite did not finish; tests on the list that pass again are
reported so the list can shrink.  Usage: suite_abgleich.py suite.log [list]
"""
import re
import sys

log = open(sys.argv[1], errors="ignore").read()
liste = sys.argv[2] if len(sys.argv) > 2 else "somonto/bekannte-abweichungen.txt"
bekannt = {z.strip() for z in open(liste, encoding="utf-8") if z.strip() and not z.startswith("#")}

if not re.search(r"^Finished in ", log, re.M):
    print("Suite did not finish (no 'Finished in' line).")
    sys.exit(1)

fehler = set(re.findall(r"^\s+\d+\) (?:test|property|doctest) (.*?) \(([\w.]+)\)\s*$", log, re.M))
fehler = {f"{modul} :: {name}" for name, modul in fehler}
neu = sorted(fehler - bekannt)
wieder_gruen = sorted(bekannt - fehler)

print(f"Failures: {len(fehler)}, known differences: {len(bekannt)}, new: {len(neu)}, passing again: {len(wieder_gruen)}")
for f in neu:
    print("NEW   ", f)
for f in wieder_gruen:
    print("GREEN ", f)
sys.exit(1 if neu else 0)
