#!/usr/bin/env python3
"""Build the Diary Sim preview as one self-contained HTML page.

Ada (compiled with AdaWebPack 24 / GNAT LLVM, the same toolchain as the
sibling spectrum-analyzer and symmetry-visualizations demos) runs the real
preview loop. JavaScript only draws. The module and the public data/ scenario
files are embedded in docs/index.html.
"""
from __future__ import annotations

import base64
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def toolchain() -> Path:
    candidates = []
    if os.environ.get("ADAWEBPACK"):
        candidates.append(Path(os.environ["ADAWEBPACK"]))
    candidates.extend([ROOT / "toolchain", Path("/tmp/adawebpack")])
    for cand in candidates:
        if (cand / "usr" / "bin" / "llvm-gcc").is_file():
            return cand
    sys.exit("AdaWebPack not found. Run tools/get-toolchain.sh")


def gnat14_include() -> Path:
    env = os.environ.get("GNAT14_ADAINCLUDE")
    if env and (Path(env) / "s-vallli.ads").is_file():
        return Path(env)
    for cand in (toolchain() / "adainclude",):
        if (cand / "s-vallli.ads").is_file():
            return cand
    hits = sorted(Path.home().glob(
        ".local/share/alire/toolchains/gnat_native_14*/lib/gcc/*/14*/adainclude"))
    for hit in hits:
        if (hit / "s-vallli.ads").is_file():
            return hit
    sys.exit("GNAT 14 adainclude not found. Set GNAT14_ADAINCLUDE (alr toolchain --select gnat_native=14.2.1).")


TOOLCHAIN = toolchain()
GNAT14 = gnat14_include()
OPT = os.environ.get("WASM_OPT", "-O0")
OBJ = ROOT / "wasm" / "obj"
RTS = OBJ / "rts"
SRC = OBJ / "src"
BUILD = OBJ / "ali"


def run(cmd: list[str], **kw) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.check_call(cmd, **kw)


def prepare_rts() -> None:
    base = TOOLCHAIN / "usr" / "lib" / "rts-native"
    if not (base / "adainclude" / "system.ads").is_file():
        sys.exit(f"AdaWebPack runtime not found at {base}. Run tools/get-toolchain.sh")
    if RTS.exists():
        shutil.rmtree(RTS)
    shutil.copytree(base, RTS)
    overlay = ROOT / "wasm" / "rts"
    for src in overlay.iterdir():
        if src.suffix in {".ads", ".adb"}:
            shutil.copy(src, RTS / "adainclude" / src.name)
    # Pure Ada string / character units the light runtime does not ship.
    for src in GNAT14.iterdir():
        if not src.suffix in {".ads", ".adb"}:
            continue
        if not (src.name.startswith("a-str") or src.name.startswith("a-ch") or src.name.startswith("a-stmaco")):
            continue
        dest = RTS / "adainclude" / src.name
        if not dest.exists():
            shutil.copy(src, dest)
    # Long_Long_Integer'Value (the seed and tick parser).  Not in the light runtime.
    for name in (
        "s-vallli.ads", "s-vallli.adb", "s-vs_lli.ads",
        "s-vafi32.ads", "s-arit32.ads", "s-arit32.adb",
        "s-valuef.ads", "s-valuef.adb", "s-valflt.ads",
        "s-imglli.ads", "s-imglli.adb", "s-bitops.ads", "s-bitops.adb",
        "s-exnflt.ads",
    ):
        src = GNAT14 / name
        dest = RTS / "adainclude" / name
        if src.is_file() and not dest.exists():
            shutil.copy(src, dest)
    unbounded = RTS / "adainclude" / "a-strunb.adb"
    if unbounded.is_file():
        unbounded.chmod(0o644)
        raw = unbounded.read_text()
        raw = raw.replace(
            "         Unreference (DR);\n\n         raise;\n   end Translate;\n",
            "         Unreference (DR);\n         return (AF.Controlled with Reference => SR);\n   end Translate;\n",
            1,
        )
        raw = raw.replace("         raise;\n", "         null;\n")
        unbounded.write_text(raw)
    write_textio_body(RTS / "adainclude" / "a-textio.adb")


def hex_of(data: bytes) -> str:
    h = data.hex()
    lines = [h[i:i + 60] for i in range(0, len(h), 60)]
    return " &\n         ".join(f'"{line}"' for line in lines)


def write_textio_body(path: Path) -> None:
    files = sorted(p for p in (ROOT / "data").iterdir() if p.is_file() and p.suffix == ".txt")
    names = [p.name for p in files]
    arms = []
    for p in files:
        arms.append(
            f'      if Base = "{p.name}" then\n'
            f'         return From_Hex (\n         {hex_of(p.read_bytes())});\n'
            f'      end if;'
        )
    membership = " | ".join(f'"{n}"' for n in names)
    body = f'''pragma Style_Checks (Off);
pragma Warnings (Off);
package body Ada.Text_IO is

   type Piece;
   type Piece_Access is access Piece;
   type Piece is record
      Text : access String;
      Next : Piece_Access;
   end record;
   Head, Tail : Piece_Access;
   Total : Natural := 0;
   Flat : access String := null;
   procedure Free_Str is new Ada.Unchecked_Deallocation (String, access String);

   function From_Hex (H : String) return String is
      R : String (1 .. H'Length / 2);
      P : Natural := R'First;
      function Val (C : Character) return Natural is
        (if C in '0' .. '9' then Character'Pos (C) - Character'Pos ('0')
         else Character'Pos (C) - Character'Pos ('a') + 10);
   begin
      while P <= R'Last loop
         declare
            I : constant Natural := H'First + (P - R'First) * 2;
         begin
            R (P) := Character'Val (Val (H (I)) * 16 + Val (H (I + 1)));
            P := P + 1;
         end;
      end loop;
      return R;
   end From_Hex;

   function Base_Name (Name : String) return String is
   begin
      for I in reverse Name'Range loop
         if Name (I) = '/' then
            return Name (I + 1 .. Name'Last);
         end if;
      end loop;
      return Name;
   end Base_Name;

   function Contents (Name : String) return String is
      Base : constant String := Base_Name (Name);
   begin
{chr(10).join(arms)}
      return "";
   end Contents;

   function Known (Name : String) return Boolean is
      Base : constant String := Base_Name (Name);
   begin
      return Base in {membership};
   end Known;

   procedure Add (S : String) is
   begin
      if S'Length = 0 then
         return;
      end if;
      declare
         P : constant Piece_Access := new Piece;
      begin
         P.Text := new String'(S);
         if Head = null then
            Head := P;
         else
            Tail.Next := P;
         end if;
         Tail := P;
         Total := Total + S'Length;
         Flat := null;
      end;
   end Add;

   Stdout_State : aliased State := (Kind => Stdout, Text => null, Pos => 1);
   Stderr_State : aliased State := (Kind => Stderr, Text => null, Pos => 1);

   procedure Create (File : in out File_Type; Mode : File_Mode; Name : String) is
      pragma Unreferenced (Mode, Name);
   begin
      File.Ptr := new State'(Kind => Disk, Text => new String'(""), Pos => 1);
   end Create;

   procedure Open (File : in out File_Type; Mode : File_Mode; Name : String) is
      pragma Unreferenced (Mode);
      Text : constant String := Contents (Name);
   begin
      if Text'Length = 0 and then not Known (Name) then
         raise Name_Error;
      end if;
      File.Ptr := new State'(Kind => Disk, Text => new String'(Text), Pos => 1);
   end Open;

   procedure Close (File : in out File_Type) is
   begin
      File.Ptr := null;
   end Close;

   function Is_Open (File : File_Type) return Boolean is (File.Ptr /= null);

   function End_Of_File (File : File_Type) return Boolean is
   begin
      if File.Ptr = null or else File.Ptr.Text = null then
         return True;
      end if;
      return File.Ptr.Pos > File.Ptr.Text'Last;
   end End_Of_File;

   function Take_Line (File : File_Type) return String is
      S : String renames File.Ptr.Text.all;
      I : Natural := File.Ptr.Pos;
      Start : constant Natural := I;
   begin
      if File.Ptr = null or else File.Ptr.Text = null or else I > S'Last then
         raise End_Error;
      end if;
      while I <= S'Last and then S (I) /= ASCII.LF loop
         I := I + 1;
      end loop;
      if I <= S'Last then
         File.Ptr.Pos := I + 1;
         if I > Start and then S (I - 1) = ASCII.CR then
            return S (Start .. I - 2);
         end if;
         return S (Start .. I - 1);
      end if;
      File.Ptr.Pos := I;
      return S (Start .. S'Last);
   end Take_Line;

   function Get_Line (File : File_Type) return String is (Take_Line (File));
   function Get_Line return String is
   begin
      raise End_Error;
      return "";
   end Get_Line;

   procedure Get_Immediate (Item : out Character; Available : out Boolean) is
   begin
      Item := ASCII.NUL;
      Available := False;
   end Get_Immediate;

   procedure Put (File : File_Type; Item : String) is
   begin
      if File.Ptr /= null and then File.Ptr.Kind = Stdout then
         Add (Item);
      end if;
   end Put;

   procedure Put (Item : String) is
   begin
      Add (Item);
   end Put;

   procedure Put_Line (File : File_Type; Item : String) is
   begin
      Put (File, Item);
      Put (File, (1 => ASCII.LF));
   end Put_Line;

   procedure Put_Line (Item : String) is
   begin
      Add (Item);
      Add ((1 => ASCII.LF));
   end Put_Line;

   procedure New_Line (File : File_Type; Spacing : Positive_Count := 1) is
   begin
      for I in 1 .. Spacing loop
         Put (File, (1 => ASCII.LF));
      end loop;
   end New_Line;

   procedure New_Line (Spacing : Positive_Count := 1) is
   begin
      for I in 1 .. Spacing loop
         Add ((1 => ASCII.LF));
      end loop;
   end New_Line;

   procedure Flush (File : File_Type) is
      pragma Unreferenced (File);
   begin
      null;
   end Flush;

   procedure Flush is
   begin
      null;
   end Flush;

   procedure Skip_Line (File : File_Type; Spacing : Positive_Count := 1) is
   begin
      for I in 1 .. Spacing loop
         declare
            Ignore : constant String := Take_Line (File);
            pragma Unreferenced (Ignore);
         begin
            null;
         end;
      end loop;
   exception
      when End_Error => null;
   end Skip_Line;

   procedure Skip_Line (Spacing : Positive_Count := 1) is
      pragma Unreferenced (Spacing);
   begin
      null;
   end Skip_Line;

   function Flatten return access String is
      R : String (1 .. Total);
      P : Natural := 1;
      C : Piece_Access := Head;
   begin
      if Flat /= null then
         return Flat;
      end if;
      while C /= null loop
         R (P .. P + C.Text'Length - 1) := C.Text.all;
         P := P + C.Text'Length;
         C := C.Next;
      end loop;
      Flat := new String'(R);
      return Flat;
   end Flatten;

   function Output_Ptr return System.Address is
      S : constant access String := Flatten;
   begin
      if S = null or else S'Length = 0 then
         return System.Null_Address;
      end if;
      return S.all'Address;
   end Output_Ptr;

   function Output_Len return Natural is
      S : constant access String := Flatten;
   begin
      if S = null then
         return 0;
      end if;
      return S'Length;
   end Output_Len;

   function Wrap (S : State_Access) return File_Type is
      R : File_Type;
   begin
      R.Ptr := S;
      return R;
   end Wrap;

   function Standard_Input return File_Type is
   begin
      return Wrap (null);
   end Standard_Input;

   function Standard_Output return File_Type is
   begin
      return Wrap (Stdout_State'Access);
   end Standard_Output;

   function Standard_Error return File_Type is
   begin
      return Wrap (Stderr_State'Access);
   end Standard_Error;

end Ada.Text_IO;
'''
    # silence unused import if Storage_Elements is unused
    body = body.replace("with System.Storage_Elements;\n", "")
    body = body.replace("   procedure Free_Str is new Ada.Unchecked_Deallocation (String, access String);\n", "")
    body = body.replace("with Ada.Unchecked_Deallocation;\n", "")
    path.write_text(body)
    print(f"embedded {len(files)} data files into {path} ({path.stat().st_size} bytes)")


def transform_text(text: str) -> str:
    import re
    text = re.sub(
        r"   type Pipe_Guard is new Ada\.Finalization\.Limited_Controlled with null record;.*?   pragma Unreferenced \(Guard\);\n",
        "   --  Pipe guard omitted in the WASM build (nested finalizers need trampolines).\n",
        text,
        count=1,
        flags=re.S,
    )
    # Generic instantiations nested in a procedure make this GNAT-LLVM build
    # trap (illegal instruction / trampoline).  Hoist the inner ones; the
    # procedure itself becomes a package body so the rest are library-level.
    hoists = []
    for snippet in (
        '         package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, Natural, Ada.Strings.Hash, "=");\n',
        '            package Nat_V is new Ada.Containers.Vectors (Positive, Natural);\n',
        '         type Pair is record E : Natural := 0; I : Natural := 0; end record;\n'
        '         package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);\n',
    ):
        if snippet not in text:
            raise SystemExit("WASM hoist pattern not found:\n" + snippet)
        text = text.replace(snippet, "", 1)
        hoists.append("   " + snippet.strip() + "\n")
    out = []
    for line in text.splitlines(True):
        if "pragma Interrupt_State" in line.split("--")[0]:
            continue
        code, sep, comment = line.partition("--")
        code = re.sub(r"\bdelay\b[^;]*;", "null;", code)
        code = re.sub(r"\bwhen\s+\w+\s*:\s*", "when ", code)
        code = re.sub(r"Ada\.Exceptions\.Exception_Message\s*\([^)]*\)", '""', code)
        code = re.sub(r"Ada\.Exceptions\.Exception_Name\s*\([^)]*\)", '""', code)
        code = re.sub(r"Ada\.Exceptions\.Exception_Information\s*\([^)]*\)", '""', code)
        code = re.sub(r"\bError_Brief\s*\(\s*\w+\s*\)", "Error_Brief (Ada.Exceptions.Null_Occurrence)", code)
        code = re.sub(r"\bReport\s*\(\s*[A-Za-z_]+\s*\)", "null", code)
        code = re.sub(r"\braise\s*;", "null;", code)
        if re.search(r"\b(Act_Of|Of_K|Used_Of|Fit|Mark|Cnt)'Access", code):
            indent = re.match(r"\s*", code).group(0)
            nl = "\n" if code.endswith("\n") else ""
            code = indent + "null;" + nl
        out.append(code + (sep + comment if sep else ""))
    text = "".join(out)
    head, rest = text.split("procedure Diary_Sim is\n", 1)
    decl, stmts = rest.split("\nbegin\n", 1)
    stmts = stmts.rsplit("\nend Diary_Sim;", 1)[0]
    # The save/night tail of the main (after the preview return) trips an
    # illegal-instruction bug in this GNAT-LLVM.  The browser entry returns
    # from Run_Preview and does not execute that tail.  Do_Tick stays.
    marker = "   if Preview then\n      Run_Preview;\n      return;\n   end if;\n"
    if marker not in stmts:
        raise SystemExit("preview return marker missing from the main statements")
    stmts = stmts.split(marker, 1)[0] + marker + "exception\n   when others =>\n      null;\n"
    return (
        head
        + "package body Diary_Core is\n"
        + "".join(hoists)
        + decl
        + "   procedure Run is\nbegin\n"
        + stmts
        + "end Run;\nend Diary_Core;\n"
    )


def prepare_sources() -> None:
    if SRC.exists():
        shutil.rmtree(SRC)
    SRC.mkdir(parents=True)
    skip = {"diary_sim.adb", "sim_quit.adb", "sim_albanian.adb", "sim_menu.adb"}
    for p in ROOT.iterdir():
        if p.suffix not in {".ads", ".adb"}:
            continue
        if p.name.startswith("b~") or p.name in skip:
            continue
        (SRC / p.name).symlink_to(p.resolve())
    (SRC / "diary_core.ads").write_text("package Diary_Core is\n   procedure Run;\nend Diary_Core;\n")
    (SRC / "diary_core.adb").write_text(transform_text((ROOT / "diary_sim.adb").read_text()))
    (SRC / "diary_sim.adb").write_text(
        "with Diary_Core;\nprocedure Diary_Sim is\nbegin\n   Diary_Core.Run;\nend Diary_Sim;\n"
    )
    (SRC / "sim_quit.adb").symlink_to((ROOT / "wasm" / "host" / "sim_quit.adb").resolve())
    (SRC / "sim_albanian.adb").symlink_to((ROOT / "wasm" / "host" / "sim_albanian.adb").resolve())
    (SRC / "sim_menu.adb").symlink_to((ROOT / "wasm" / "host" / "sim_menu.adb").resolve())


def compile_and_link() -> Path:
    gcc = TOOLCHAIN / "usr" / "bin" / "llvm-gcc"
    gmake = TOOLCHAIN / "usr" / "bin" / "llvm-gnatmake"
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = str(TOOLCHAIN / "lib") + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)
    adainc = RTS / "adainclude"
    for name in (
        "a-calend.adb", "a-calfor.adb", "a-comlin.adb", "a-envvar.adb",
        "a-direct.adb", "a-ststio.adb", "a-textio.adb", "g-os_lib.adb",
        "g-trasym.adb", "s-atocou.adb", "a-strunb.adb", "a-strmap.adb",
        "a-strfix.adb", "a-strsea.adb", "a-strhas.adb", "a-chahan.adb",
        "a-chlat1.ads", "s-bitops.adb", "a-stmaco.ads", "gnat.ads",
        "g-traceb.ads", "a-contai.ads",
    ):
        stem = name.rsplit(".", 1)[0]
        run([
            str(gcc), "-c", "-gnatg", f"--RTS={RTS}", "--target=wasm32", OPT, "-gnat2022",
            name, "-o", str(BUILD / f"{stem}.o"),
        ], env=env, cwd=adainc)
        for ext in (".ali", ".o"):
            srcp = BUILD / f"{stem}{ext}"
            if srcp.is_file():
                shutil.copy(srcp, RTS / "adalib" / srcp.name)
    # -D takes a separate argument. Glued on, gnatmake forwards it to gcc as a
    # macro and writes every object into the working directory.
    stale = set(ROOT.glob("*.ali")) | set(ROOT.glob("*.o")) | set(ROOT.glob("b~*"))
    for path in stale:
        path.unlink(missing_ok=True)
    # -D takes a separate directory argument. -I must be glued; a separated
    # -I is reported as "missing source directory name".
    run([
        str(gmake), f"--RTS={RTS}", "-D", str(BUILD), f"-I{SRC}",
        str(SRC / "diary_sim.adb"),
        "-c",
        "-cargs", OPT, "-gnat2022", "-gnatw.X", "--target=wasm32",
    ], env=env, cwd=BUILD)
    bind = TOOLCHAIN / "usr" / "bin" / "llvm-gnatbind"
    satisfy_binder(env, gcc, bind)
    # -o must be a relative name. An absolute path lands in a Source_File_Name
    # pragma, and this compiler rejects the directory separator.
    run([
        str(gcc), "-c", f"--RTS={RTS}", "--target=wasm32", OPT, "-gnat2022",
        f"-I{SRC}", "b~diary_sim.adb", "-o", "b~diary_sim.o",
    ], env=env, cwd=BUILD)
    rt_o = OBJ / "rt.o"
    run(["clang", "--target=wasm32", "-c", "-O2", str(ROOT / "wasm" / "rt.c"), "-o", str(rt_o)])
    # Keep only wasm members of libgnat.
    lib = RTS / "adalib" / "libgnat.a"
    pick = OBJ / "libgnat-wasm.a"
    filt = r'''
import os, subprocess, sys
src, dst, tmp = sys.argv[1:]
os.makedirs(tmp, exist_ok=True)
members = subprocess.check_output(["ar", "t", src], text=True).split()
keep = []
for i, member in enumerate(members):
    data = subprocess.check_output(["ar", "p", src, member])
    if data.startswith(b"\0asm") or data.startswith(b"BC\xc0\xde"):
        path = os.path.join(tmp, f"{i:04d}-{member}")
        open(path, "wb").write(data)
        keep.append(path)
subprocess.check_call(["ar", "rcs", dst, *keep])
print(f"libgnat wasm members {len(keep)} / {len(members)}")
'''
    subprocess.check_call([sys.executable, "-c", filt, str(lib), str(pick), str(OBJ / "rts-pick")])
    objs = sorted(BUILD.glob("*.o"))
    wasm = OBJ / "diary_sim.wasm"
    run([
        "wasm-ld", "--no-entry", "--export-memory", "--strip-all",
        "--export=adainit", "--export=adafinal", "--export=_ada_diary_sim",
        "--export=ds_set_seed", "--export=ds_set_ticks",
        "--export=ds_out_ptr", "--export=ds_out_len",
        "--export=ds_exc", "--export=ds_exc_len", "--export=ds_exc_line",
        "-z", "stack-size=8388608",
        "--initial-memory=134217728", "--max-memory=268435456",
        "-o", str(wasm),
        *map(str, objs), str(rt_o), str(pick),
    ])
    print(f"wasm {wasm.stat().st_size} bytes")
    return wasm


def satisfy_binder(env: dict, gcc: Path, bind: Path) -> None:
    """Compile any runtime spec the binder still lacks, then bind.

    Predefined units are resolved from the runtime library, so an ALI that
    exists only beside a user object is not enough. The binder names one
    missing unit at a time; sources that the light runtime does not ship are
    copied from the GNAT 14 adainclude.
    """
    missing = re.compile(r'"([^"]+)" must be compiled')
    adainc = RTS / "adainclude"
    for _ in range(24):
        proc = subprocess.run(
            [str(bind), f"--RTS={RTS}", f"-aO{BUILD}", f"-aI{SRC}", f"-I{BUILD}",
             "-n", "-x", "-o", "b~diary_sim.adb", "diary_sim.ali"],
            cwd=BUILD, capture_output=True, text=True, env=env,
        )
        if proc.returncode == 0:
            print("+ gnatbind", flush=True)
            return
        text = (proc.stdout or "") + (proc.stderr or "")
        needed: list[str] = []
        for line in text.splitlines():
            match = missing.search(line)
            if match and match.group(1) not in needed:
                needed.append(match.group(1))
        if not needed:
            sys.stderr.write(text)
            raise SystemExit("gnatbind failed")
        print("binder needs " + ", ".join(needed), flush=True)
        for name in needed:
            src = adainc / name
            if not src.is_file():
                alt = GNAT14 / name
                if not alt.is_file():
                    sys.stderr.write(text)
                    raise SystemExit(f"runtime source missing: {name}")
                shutil.copy(alt, src)
            stem = name.rsplit(".", 1)[0]
            run([
                str(gcc), "-c", "-gnatg", f"--RTS={RTS}", "--target=wasm32", OPT, "-gnat2022",
                name, "-o", str(BUILD / f"{stem}.o"),
            ], env=env, cwd=adainc)
            for ext in (".ali", ".o"):
                produced = BUILD / f"{stem}{ext}"
                if not produced.is_file():
                    produced = adainc / f"{stem}{ext}"
                if produced.is_file():
                    shutil.copy(produced, RTS / "adalib" / f"{stem}{ext}")
                    if produced.parent == adainc:
                        produced.unlink()
    raise SystemExit("gnatbind did not settle")


def write_page(wasm: Path) -> None:
    template = (ROOT / "tools" / "demo_template.html").read_text()
    token = "@@WASM_BASE64@@"
    if token not in template:
        raise SystemExit("demo template is missing the wasm placeholder")
    encoded = base64.b64encode(wasm.read_bytes()).decode("ascii")
    page = template.replace(token, encoded)
    dest = ROOT / "docs" / "index.html"
    dest.write_text(page)
    print(f"page {dest} ({dest.stat().st_size} bytes)")


def main() -> None:
    os.chdir(ROOT)
    prepare_rts()
    prepare_sources()
    wasm = compile_and_link()
    write_page(wasm)


if __name__ == "__main__":
    main()
