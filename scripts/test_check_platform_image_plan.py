"""check_platform_image_plan 단위 테스트. 실행: python3 -m unittest discover -s scripts"""

import copy
import json
import unittest

from check_platform_image_plan import SERVICE, TASK_DEFINITION, check_plan

REPO = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sky-platform"
OLD = REPO + ":aaaaaaa"
NEW = REPO + ":bbbbbbb"


def containers(image, **extra):
    c = {
        "name": "sky-platform",
        "image": image,
        "essential": True,
        "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
        "environment": [{"name": "SKY_AWS_REGION", "value": "ap-northeast-2"}],
        "mountPoints": [{"sourceVolume": "state", "containerPath": "/app/.sky", "readOnly": False}],
    }
    c.update(extra)
    return json.dumps([c])


def task_definition_change(before_image=OLD, after_image=NEW, after_extra=None, cpu_after="1024"):
    return {
        "address": TASK_DEFINITION,
        "mode": "managed",
        "change": {
            "actions": ["delete", "create"],
            "before": {
                "arn": "arn:aws:ecs:ap-northeast-2:123456789012:task-definition/sky-dev-platform:3",
                "revision": 3,
                "cpu": "1024",
                "family": "sky-dev-platform",
                "container_definitions": containers(before_image),
            },
            "after": {
                "cpu": cpu_after,
                "family": "sky-dev-platform",
                "container_definitions": containers(after_image, **(after_extra or {})),
            },
            "after_unknown": {"arn": True, "revision": True},
        },
    }


def service_change(actions=None, desired_after=1):
    return {
        "address": SERVICE,
        "mode": "managed",
        "change": {
            "actions": actions or ["update"],
            "before": {"task_definition": "arn:...:3", "desired_count": 1, "name": "sky-dev-platform"},
            "after": {"desired_count": desired_after, "name": "sky-dev-platform"},
            "after_unknown": {"task_definition": True},
        },
    }


def plan(*changes):
    return {"resource_changes": list(changes)}


class CheckPlanTest(unittest.TestCase):
    def test_image_only_change_passes(self):
        errors, changed = check_plan(plan(task_definition_change(), service_change()), NEW)
        self.assertEqual(errors, [])
        self.assertEqual(len(changed), 2)

    def test_no_change_passes(self):
        noop = copy.deepcopy(service_change())
        noop["change"]["actions"] = ["no-op"]
        errors, changed = check_plan(plan(noop), NEW)
        self.assertEqual((errors, changed), ([], []))

    def test_data_sources_are_ignored(self):
        data = {"address": "module.ecs.data.aws_ssm_parameter.ecs_ami", "mode": "data",
                "change": {"actions": ["read"]}}
        errors, _ = check_plan(plan(data, task_definition_change(), service_change()), NEW)
        self.assertEqual(errors, [])

    def test_state_list_order_and_empty_values_are_ignored(self):
        tdc = task_definition_change()
        before = json.loads(tdc["change"]["before"]["container_definitions"])
        before[0]["environment"] = [{"name": "B", "value": "2"}, {"name": "A", "value": "1"}]
        before[0]["volumesFrom"] = []
        before[0]["mountPoints"][0].pop("readOnly")
        tdc["change"]["before"]["container_definitions"] = json.dumps(before)
        after = json.loads(tdc["change"]["after"]["container_definitions"])
        after[0]["environment"] = [{"name": "A", "value": "1"}, {"name": "B", "value": "2"}]
        tdc["change"]["after"]["container_definitions"] = json.dumps(after)
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertEqual(errors, [])

    def test_other_resource_change_fails(self):
        lt = {"address": "module.ecs.aws_launch_template.this", "mode": "managed",
              "change": {"actions": ["update"], "before": {}, "after": {}, "after_unknown": {}}}
        errors, _ = check_plan(plan(lt, task_definition_change(), service_change()), NEW)
        self.assertTrue(any("aws_launch_template" in e for e in errors))

    def test_container_change_besides_image_fails(self):
        tdc = task_definition_change(after_extra={"environment": [{"name": "X", "value": "1"}]})
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertTrue(any("이미지 외 값" in e for e in errors))

    def test_task_definition_attribute_change_fails(self):
        errors, _ = check_plan(plan(task_definition_change(cpu_after="2048"), service_change()), NEW)
        self.assertTrue(any("'cpu'" in e for e in errors))

    def test_unexpected_image_fails(self):
        errors, _ = check_plan(plan(task_definition_change(after_image=REPO + ":ccccccc"), service_change()), NEW)
        self.assertTrue(any("기대값과 다르다" in e for e in errors))

    def test_task_definition_in_place_update_fails(self):
        tdc = task_definition_change()
        tdc["change"]["actions"] = ["update"]
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertTrue(any("교체만 허용" in e for e in errors))

    def test_service_replace_fails(self):
        errors, _ = check_plan(plan(task_definition_change(), service_change(["delete", "create"])), NEW)
        self.assertTrue(any("제자리 수정만" in e for e in errors))

    def test_service_other_attribute_fails(self):
        errors, _ = check_plan(plan(task_definition_change(), service_change(desired_after=2)), NEW)
        self.assertTrue(any("'desired_count'" in e for e in errors))

    def test_errored_plan_fails(self):
        p = plan(task_definition_change(), service_change())
        p["errored"] = True
        errors, _ = check_plan(p, NEW)
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
