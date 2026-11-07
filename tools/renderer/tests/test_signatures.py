"""Run with python3 -m unittest discover -s tools/renderer/tests -p 'test_*.py'."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

NATIVE = Path(__file__).resolve().parents[1] / 'native'

# Bytes read from running games, so a signature edit cannot silently lose a build.
BUILDS = {
    '3.9.0.401155': {
        'INIT': '48895C24205556574154415541564157488DAC2490FEFFFF4881EC70020000488B051AD809094833C448898560010000498BF0488BFA4C8BF148895424484533ED4C8B394D8B6718B950020000E88E2E83FE',
        'DEFERRED': '40534883EC30E8C571FDFF488BD84885C07535488D05C6BFFF0541B8410000004C8D0D09C0FF054889442420488D154DC0FF05488D0D76BFFF05E811B504FF84C07405E8E8B404FFE84371FDFF83C0FD83F8077738',
        'STRUCTURED_CREATE': '4883EC380FB7C2458BD048C1E0054881C148540500C7442428020000004803C844894C24204533C0440FB74C2460418BD2E83A86FFFF',
        'STRUCTURED_UPDATE': '4883EC384D8B084881C148540500458B40080FB7C233D248C1E0054803C8C644242800C644242001E80389FFFF',
        'CAPS_GETTER': '488D05B9ACF40AC3CCCCCCCC',
    },
    '3.10.0.420447': {
        'INIT': '48895c24205556574154415541564157488dac24e0fdffff4881ec20030000488b05dad976094833c448898510020000498bf84c8bf2488bf148895424484533ed4c8b394d8b6718b9f8020000e80e1aee00',
        'DEFERRED': '40534883EC30E875121100488BD84885C07535488D05A615090641B8410000004C8D0DE91509064889442420488D152D160906488D0D5E150906E861AA4B0184C07405E848884B01E85318110083C0FD83F8077738',
        'DESTROY': '48895c2410564883ec30488b511833f6488bd94885d27425488b0d318eff0a4885c97415488b014533c9897424284533c04889742420ff500848897318488b4b10',
        'STRUCTURED_CREATE': '4883EC380FB7C2458BD048C1E0054881C148540500C7442428020000004803C844894C24204533C0440FB74C2460418BD2E80AE2FFFF',
        'STRUCTURED_UPDATE': '4883ec384d8b084881c148540500458b40080fb7c233d248c1e0054803c8c644242800c644242001e833f2ffff',
        'CAPS_GETTER': '488d0549cf020bc3cccccccc',
    },
    '3.10.0.448891': {
        'DEFERRED': '40534883EC30E895A81100488BD84885C07535488D0506CE0F0641B8410000004C8D0D49CE0F064889442420488D158DCE0F06488D0DBECD0F06E8C15F510184C07405E8A83D5101E873AE110083C0FD83F8077738',
        'STRUCTURED_CREATE': '4883EC380FB7C2458BD048C1E0054881C148540500C7442428020000004803C844894C24204533C0440FB74C2460418BD2E80AE2FFFF',
        'CAPS_GETTER': '488D05F9AA0A0BC3CCCCCCCC',
    },
}

HARNESS = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "signatures.h"
int main(int argc, char **argv) {
    Signature signature;
    if (!signature_parse(argv[1], &signature)) { puts("invalid"); return 0; }
    size_t size = strlen(argv[2]) / 2;
    uint8_t *data = malloc(size + 1);
    for (size_t i = 0; i < size; i++) {
        unsigned value; sscanf(argv[2] + i * 2, "%2x", &value); data[i] = (uint8_t)value;
    }
    const uint8_t *found = NULL;
    int hits = signature_search(data, size, &signature, &found);
    printf("%d %ld\n", hits, found ? (long)(found - data) : -1L);
    return 0;
}
'''


class SignatureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        source = Path(cls.temp.name) / 'harness.c'
        source.write_text(HARNESS)
        cls.binary = Path(cls.temp.name) / 'harness'
        subprocess.run(['cc', '-I', str(NATIVE), '-o', str(cls.binary), str(source)], check=True)
        header = (NATIVE / 'signatures.h').read_text()
        cls.signatures = dict(re.findall(r'#define SIGNATURE_(\w+) "([^"]+)"', header))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def search(self, pattern, data):
        return subprocess.run([str(self.binary), pattern, data], check=True,
                              capture_output=True, text=True).stdout.strip()

    def test_every_signature_matches_the_bytes_of_every_recorded_build(self):
        for build, functions in BUILDS.items():
            for name, data in functions.items():
                with self.subTest(build=build, name=name):
                    self.assertEqual(self.search(self.signatures[name], data), '1 0')

    def test_signatures_do_not_match_each_other(self):
        data = BUILDS['3.10.0.420447']
        for name, pattern in self.signatures.items():
            for other, bytes_ in data.items():
                if name != other:
                    with self.subTest(name=name, other=other):
                        self.assertEqual(self.search(pattern, bytes_).split()[0], '0')

    def test_search_counts_duplicates_and_reports_the_first(self):
        self.assertEqual(self.search('aa ?? cc', '00aa01cc00aa02cc'), '2 1')

    def test_wildcards_do_not_accept_a_changed_known_byte(self):
        self.assertEqual(self.search('aa ?? cc', 'aa01cd'), '0 -1')

    def test_match_at_the_very_end_is_found(self):
        self.assertEqual(self.search('aa bb', '0000aabb'), '1 2')

    def test_malformed_signatures_are_rejected(self):
        self.assertEqual(self.search('aa b', '00'), 'invalid')
        self.assertEqual(self.search('zz', '00'), 'invalid')


if __name__ == '__main__':
    unittest.main()
