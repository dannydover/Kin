import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
p=pathlib.Path(__file__).with_name('product_manifest.py');s=importlib.util.spec_from_file_location('ab_product',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class ProductTests(unittest.TestCase):
 def test_files_modes_links_and_escapes(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d)/'products';root.mkdir();f=root/'runner';f.write_bytes(b'synthetic');f.chmod(0o755)
   (root/'alias').symlink_to('runner');before=m.manifest(root)
   self.assertEqual({x['kind'] for x in before},{'file','link'})
   f.write_bytes(b'changed');self.assertNotEqual(before,m.manifest(root));f.write_bytes(b'synthetic');f.chmod(0o644)
   self.assertNotEqual(before,m.manifest(root))
   (root/'escape').symlink_to('/tmp')
   with self.assertRaises(ValueError):m.manifest(root)
 def test_ditto_roundtrip_preserves_manifest(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d)/'Products';root.mkdir();f=root/'runner';f.write_bytes(b'synthetic');f.chmod(0o755)
   (root/'alias').symlink_to('runner');expected=m.manifest(root)
   archive=pathlib.Path(d)/'products.zip';out=pathlib.Path(d)/'out';out.mkdir()
   subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(root),str(archive)],check=True)
   subprocess.run(['ditto','-x','-k',str(archive),str(out)],check=True)
   self.assertEqual(expected,m.manifest(out/'Products'))
 def test_empty_fails_closed(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):m.manifest(d)
if __name__=='__main__':unittest.main()
