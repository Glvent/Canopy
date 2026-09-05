#!/usr/bin/env python3
"""Run pinned upstream tests and capture non-CJK inputs and widths as TSV.

The three exhaustive scalar loops run at every property interval boundary and
its neighbors. Other upstream tests run unchanged, including official emoji.
Grapheme corpus contains every upstream official Unicode 17 extended case.
"""
import json, pathlib, re, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
registry = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else next((pathlib.Path.home()/".cargo/registry/src").glob("*"))
seg = registry/"unicode-segmentation-1.13.3"
width = registry/"unicode-width-0.2.2"
header = """
#[allow(dead_code)] mod width { include!(WIDTH); }
fn hex(s: &str) -> String { s.as_bytes().iter().map(|b|format!("{b:02x}")).collect() }
mod wrapped {
pub trait UnicodeWidthChar {fn width(self) -> Option<usize>;}
impl UnicodeWidthChar for char {fn width(self) -> Option<usize> {super::width::single_char_width(self)}}
pub trait UnicodeWidthStr {fn width(&self) -> usize;}
impl UnicodeWidthStr for str {fn width(&self) -> usize {
let w=super::width::str_width(self); println!("{}\\t{}",super::hex(self),w); w
}}
}
""".replace("WIDTH",json.dumps(str(width/"src/tables.rs")))
body=(width/"tests/tests.rs").read_text().replace("use unicode_width::", "use wrapped::").replace("#[test]", "")
body=body.replace('dbg!(&emoji);','')
body=body.replace('File::open("tests/emoji-test.txt")','File::open('+json.dumps(str(width/"tests/emoji-test.txt"))+')')
points=set()
for first,last in re.findall(r"^  \((\d+), (\d+),",(root/"src/canopy/internal/unicode/tables.nim").read_text(),re.M):
    for p in (int(first),int(last)):
        points.update(q for q in (p-1,p,p+1) if 0<=q<=0x10FFFF and not 0xD800<=q<=0xDFFF)
body=body.replace("for c in '\\0'..=char::MAX", "for c in PROBES.iter().filter_map(|cp|char::from_u32(*cp))")
functions=re.findall(r"^fn (\w+)\(\)",body,re.M)
source=header+"const PROBES: &[u32] = &["+",".join(map(str,sorted(points)))+"];\n"+body+"\nfn main(){"+"".join(f"{f}();" for f in functions)+"}"
with tempfile.TemporaryDirectory() as temp:
    temp=pathlib.Path(temp)
    def run(source):
        (temp/"fixture.rs").write_text(source)
        subprocess.run(["rustc","--edition=2021","-Awarnings",str(temp/"fixture.rs"),"-o",str(temp/"fixture")],check=True)
        return subprocess.check_output([str(temp/"fixture")],text=True)
    records=sorted(set(run(source).splitlines()))
    (root/"tests/unicode/width.tsv").write_text("# unicode-width 0.2.2 upstream tests; UTF-8 hex TAB non-CJK string width\n"+"\n".join(records)+"\n")
    grapheme=header.split("mod wrapped")[0]+"#[path="+json.dumps(str(seg/"tests/testdata/mod.rs"))+"] mod data;\n"
    grapheme+='fn main(){for (s,g) in data::TEST_SAME {println!("{}\\t{}",hex(s),g.iter().map(|s|hex(s)).collect::<Vec<_>>().join(" "));} for (s,g,_) in data::TEST_DIFF {println!("{}\\t{}",hex(s),g.iter().map(|s|hex(s)).collect::<Vec<_>>().join(" "));}}'
    cases=run(grapheme)
    (root/"tests/unicode/graphemes.tsv").write_text("# Unicode 17 GraphemeBreakTest.txt via unicode-segmentation 1.13.3; input hex TAB clusters\n"+cases)
print(f"Captured {len(records)} width cases at {len(points)} scalar probes, {len(cases.splitlines())} official grapheme cases")
