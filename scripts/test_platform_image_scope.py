import unittest
from platform_image_scope import IMAGE_FILE, image_only


class ImageScopeTests(unittest.TestCase):
    def test_only_image_is_eligible(self):
        self.assertTrue(image_only([IMAGE_FILE]))

    def test_structural_pr_cannot_reach_image_deployment(self):
        self.assertFalse(image_only([IMAGE_FILE, "modules/aws/iam/main.tf"]))
        self.assertFalse(image_only([]))
        self.assertFalse(image_only(["modules/aws/ecs/main.tf"]))
