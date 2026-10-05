import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from PIL import Image

spec = importlib.util.spec_from_file_location('patch_platforms', Path(__file__).with_name('patch_platforms.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class IconTests(unittest.TestCase):
    def test_generated_platform_icons_use_new_source_and_valid_sizes(self):
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as temp:
            try:
                os.chdir(temp)
                Path('assets/icon').mkdir(parents=True)
                Image.new('RGBA', (1024, 1024), (10, 220, 30, 255)).save('assets/icon/app_icon.png')
                for folder in ('windows/runner/resources', 'android/app/src/main/res',
                               'ios/Runner/Assets.xcassets/AppIcon.appiconset',
                               'macos/Runner/Assets.xcassets/AppIcon.appiconset'):
                    Path(folder).mkdir(parents=True)
                module.make_icons()
                with Image.open('windows/runner/resources/app_icon.ico') as icon:
                    self.assertIn((256, 256), icon.ico.sizes())
                    self.assertIn((16, 16), icon.ico.sizes())
                with Image.open('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png') as icon:
                    self.assertEqual(icon.size, (192, 192))
                    self.assertEqual(icon.getpixel((96, 96)), (10, 220, 30, 255))
                for platform, count in (('ios', 18), ('macos', 10)):
                    folder = Path(f'{platform}/Runner/Assets.xcassets/AppIcon.appiconset')
                    config = json.loads((folder / 'Contents.json').read_text())
                    self.assertEqual(len(config['images']), count)
                    for item in config['images']:
                        size = round(float(item['size'].split('x')[0]) * int(item['scale'][0]))
                        with Image.open(folder / item['filename']) as icon:
                            self.assertEqual(icon.size, (size, size))
                            self.assertEqual(icon.mode, 'RGB')
                            self.assertEqual(icon.getpixel((size//2, size//2)), (10, 220, 30))
            finally:
                os.chdir(original)
