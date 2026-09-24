#!/usr/bin/env python3
"""Render query.sh CSV as a padded Markdown pipe table.

    query.sh <file.sql> name=value ... | python3 ../_shared/scripts/render.py

Cells are padded so the table is aligned as plain text in a terminal, and the pipes plus the
alignment row mean Slack and GitHub render it as a real table. One output, both readers.

Numeric columns are right-aligned. Empty input passes through untouched, because query.sh has
already said on stderr that the query matched nothing.
"""
import csv
import sys


def is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def main():
    rows = list(csv.reader(sys.stdin))
    if not rows:
        return
    head, data = rows[0], rows[1:]
    # A column is numeric only if every non-empty value in it is, so a column of counts stays
    # right-aligned while one carrying "-" or a label does not.
    right = {
        c for c in range(len(head))
        if data and all(is_number(r[c]) for r in data if c < len(r) and r[c] != "")
    }
    width = [
        max([len(head[c])] + [len(r[c]) for r in data if c < len(r)])
        for c in range(len(head))
    ]

    def line(cells):
        out = []
        for c, value in enumerate(cells):
            out.append(value.rjust(width[c]) if c in right else value.ljust(width[c]))
        return "| " + " | ".join(out) + " |"

    rule = "|" + "|".join(
        ("-" * (width[c] + 1) + ":") if c in right else (":" + "-" * (width[c] + 1))
        for c in range(len(head))
    ) + "|"

    print(line(head))
    print(rule)
    for r in data:
        print(line(r + [""] * (len(head) - len(r))))


if __name__ == "__main__":
    main()
