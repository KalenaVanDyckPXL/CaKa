"""
Proves that the Ancient Oracle answers the same at every hour of the day.

The test fakes the Kubernetes API with a fixed set of objects, pins the
realm's clock to 10:00, 14:00 and 16:00, and checks that every tool returns
exactly the cluster's data, with no shed items, renamed pods, changed phases,
jittered counters or injected "guidance".

Run from images/ancient-oracle:

    python3 -m unittest discover -s tests -v

If a runtime/sitecustomize.py exists, it is loaded first, as the Python
image does at start-up, so a shim that patches the standard library is
caught too.
"""

import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

# Load the image's runtime shims the way site-packages would.
_shim = os.path.join(ROOT, "runtime", "sitecustomize.py")
if os.path.exists(_shim):
    spec = importlib.util.spec_from_file_location("sitecustomize", _shim)
    spec.loader.exec_module(importlib.util.module_from_spec(spec))

os.environ["ORACLE_JOURNAL"] = os.path.join(tempfile.mkdtemp(), "journal.jsonl")

from oracle import server, tools  # noqa: E402


def _pod(ns, name, phase="Running", restarts=0):
    return {
        "metadata": {"namespace": ns, "name": name,
                     "creationTimestamp": "2026-01-01T00:00:00Z"},
        "spec": {"nodeName": "node-1", "containers": [{"name": "c"}]},
        "status": {"phase": phase,
                   "containerStatuses": [{"name": "c", "ready": phase == "Running",
                                          "restartCount": restarts}]},
    }


PODS = [
    _pod("scrolls", "scrolls-app-7d9f8c6b4d-x2kq9", restarts=7),
    _pod("scrolls", "magician-5c8d7f9b6c-ab12c", restarts=3),
    _pod("oracle", "ixeth-6f7d8c9b5d-qwe12", restarts=1),
    _pod("oracle", "grimoire-7b8c9d6f5e-zxc34"),
    _pod("oracle", "alertmanager-5d6e7f8a9b-poi98"),
    _pod("ancient", "ancient-oracle-6c7d8e9f0a-lkj76", restarts=2),
    _pod("scrolls", "broken-6d7e8f9a0b-mnb54", phase="Pending"),
]

DEPLOYMENTS = [
    {"metadata": {"namespace": "scrolls", "name": n},
     "spec": {"replicas": r, "template": {"spec": {"containers": [{"image": "busybox:1.37.0"}]}}},
     "status": {"readyReplicas": r, "updatedReplicas": r, "availableReplicas": r}}
    for n, r in (("scrolls-app", 1), ("magician", 1), ("broken", 3))
]

NODES = [
    {"metadata": {"name": f"node-{i}"},
     "status": {"conditions": [{"type": "Ready", "status": "True"}],
                "nodeInfo": {"kubeletVersion": "v1.33.1"},
                "allocatable": {"cpu": "8", "memory": "30Gi", "pods": "110"}}}
    for i in (1, 2)
]


def fake_request(self, path, params=None, raw=False):
    if path.endswith("/pods"):
        items = PODS
    elif path.endswith("/deployments"):
        items = DEPLOYMENTS
    elif path.endswith("/nodes"):
        items = NODES
    else:
        items = []
    return {"items": json.loads(json.dumps(items))}  # fresh copy per call


def at_hour(hour):
    """Pins every clock the Oracle could read to `hour` local time today."""
    base = time.mktime(time.struct_time((2026, 11, 24, hour, 0, 0, 1, 328, -1)))
    real_localtime = time.localtime
    return [
        mock.patch("time.time", return_value=base),
        mock.patch("time.localtime", side_effect=lambda t=None: real_localtime(base if t is None else t)),
        mock.patch.object(tools.kube, "skew", 0.0),
    ]


class OracleIsTruthfulAllDay(unittest.TestCase):
    CALLS = 25  # randomness has to lose every time, not just once

    def setUp(self):
        p = mock.patch("oracle.kube.Kube.request", fake_request)
        p.start()
        self.addCleanup(p.stop)

    def ask(self, hour, tool, args=None):
        patches = at_hour(hour)
        for p in patches:
            p.start()
        try:
            result = server.answer(tool, args or {}, "test")
        finally:
            for p in reversed(patches):
                p.stop()
        self.assertFalse(result["isError"], result)
        self.assertEqual(len(result["content"]), 1, f"extra content at {hour}:00: {result['content'][1:]}")
        return json.loads(result["content"][0]["text"])

    def check_all(self, tool, key, expected):
        truth = self.ask(10, tool)
        self.assertEqual(truth["count"], expected)
        for hour in (10, 14, 15, 16, 18, 23):
            for _ in range(self.CALLS):
                with self.subTest(tool=tool, hour=hour):
                    self.assertEqual(self.ask(hour, tool), truth)

    def test_pods(self):
        self.check_all("list_pods", "pods", len(PODS))

    def test_deployments(self):
        self.check_all("list_deployments", "deployments", len(DEPLOYMENTS))

    def test_nodes(self):
        self.check_all("list_nodes", "nodes", len(NODES))

    def test_restart_counts_are_exact(self):
        pods = {p["name"]: p["restarts"] for p in self.ask(16, "list_pods")["pods"]}
        self.assertEqual(pods["scrolls-app-7d9f8c6b4d-x2kq9"], 7)
        self.assertEqual(pods["magician-5c8d7f9b6c-ab12c"], 3)


if __name__ == "__main__":
    unittest.main()
