"""the single compliance driver: runs every flow (flows.py) against every
selected frontend and prints a frontend x flow result matrix. because all
frontends run the same flow code, they cannot drift; a flow an frontend cannot
perform is reported "skip", a broken flow "FAIL"/"ERR".

usage: uv run matrix.py [--linux] [--android] [--web]
exit code is non-zero if any flow FAILed or errored (skips are fine)."""

import argparse
import sys

import flows
from frontend import SkipFlow


def _run_on(front, flow_list):
    res = {}
    for name, fn in flow_list:
        try:
            front.reset()
            fn(front)
            res[name] = ("pass", "")
        except SkipFlow as e:
            res[name] = ("skip", str(e))
        except AssertionError as e:
            res[name] = ("fail", str(e) or "assertion failed")
        except Exception as e:  # noqa: BLE001 - report, do not crash the matrix
            res[name] = ("error", f"{type(e).__name__}: {e}")
    return res


def run(frontend_classes, flow_list):
    results = {}
    for cls in frontend_classes:
        front = cls()
        try:
            front.start()
        except Exception as e:  # noqa: BLE001
            results[cls.name] = {
                n: ("error", f"start: {e}") for n, _ in flow_list
            }
            continue
        try:
            results[cls.name] = _run_on(front, flow_list)
        finally:
            try:
                front.stop()
            except Exception:
                pass
    return results


def print_matrix(results, flow_list):
    names = [n for n, _ in flow_list]
    fronts = list(results.keys())
    w = max(len(n) for n in names) + 2
    glyph = {"pass": "PASS", "skip": "skip", "fail": "FAIL", "error": "ERR "}
    header = "flow".ljust(w) + "".join(f.ljust(10) for f in fronts)
    print(header)
    print("-" * len(header))
    for n in names:
        row = n.ljust(w)
        for f in fronts:
            st = results[f].get(n, ("?", ""))[0]
            row += glyph.get(st, st).ljust(10)
        print(row)
    bad = [
        f"[{f}] {n}: {st}: {msg}"
        for f in fronts
        for n in names
        for st, msg in [results[f].get(n, ("?", ""))]
        if st in ("fail", "error")
    ]
    if bad:
        print("\nfailures:")
        for b in bad:
            print("  " + b)
    return not bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--linux", action="store_true")
    ap.add_argument("--android", action="store_true")
    ap.add_argument("--web", action="store_true")
    ap.add_argument(
        "--single", action="store_true", help="run only single-device flows"
    )
    ap.add_argument(
        "--collab", action="store_true", help="run only collaboration flows"
    )
    ap.add_argument(
        "--flow",
        action="append",
        default=[],
        help="run only these flow names (repeatable)",
    )
    args = ap.parse_args()
    if args.collab:
        flow_list = flows.COLLAB
    elif args.single:
        flow_list = flows.SINGLE
    else:
        flow_list = flows.ALL
    if args.flow:
        flow_list = [(n, fn) for n, fn in flow_list if n in args.flow]
        if not flow_list:
            print(f"no flows match {args.flow}")
            sys.exit(2)

    frontends = []
    if args.linux:
        from linux_frontend import LinuxFrontend

        frontends.append(LinuxFrontend)
    if args.android:
        from android_frontend import AndroidFrontend

        frontends.append(AndroidFrontend)
    if args.web:
        from web_frontend import WebFrontend

        frontends.append(WebFrontend)
    if not frontends:
        print("specify at least one of --linux --android --web")
        sys.exit(2)

    ok = print_matrix(run(frontends, flow_list), flow_list)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
