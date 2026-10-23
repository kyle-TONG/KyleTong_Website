"""Turn the three PSID downloads into small CSV files for the tutorial.

Run from the project root:

    python blog/posts/post6.2/py/01_prepare.py

Inputs (data/raw/, not committed; PSID does not allow redistribution):
    ind2023er.zip   cross-year individual file, 1968-2023 (packaged release)
    pid23.zip       Parent Identification File, 2023
    J366546.zip     Data Center family-file extract: labor income of the reference
                    person and spouse in the 2017, 2019, 2021 and 2023 waves

Outputs (data/psid/, not committed):
    individuals.csv     one row per person: IDs, sex, and interview number, sequence
                        number, relation to reference person and age in each wave
    family_income.csv   one row per family per wave: labor income of the reference
                        person and of the spouse/partner
    parents.csv         each person's birth mother and birth father
"""

import io
import re
import zipfile
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent.parent
RAW = HERE / "data" / "raw"
OUT = HERE / "data" / "psid"
OUT.mkdir(parents=True, exist_ok=True)

WAVES = [2017, 2019, 2021, 2023]


def infix_positions(do_text):
    """Read 'VAR  start - end' pairs from the infix block of a PSID .do file."""
    return {m[0]: (int(m[1]) - 1, int(m[2]))
            for m in re.findall(r"(\w+)\s+(\d+)\s*-\s*(\d+)", do_text)}


def read_fixed_width(zf, txt_name, do_name, wanted):
    """Read only the wanted columns of a fixed-width PSID text file inside a zip."""
    pos = infix_positions(zf.read(do_name).decode("latin-1"))
    spans = [pos[v] for v in wanted]
    with zf.open(txt_name) as f:
        return pd.read_fwf(f, colspecs=spans, names=wanted, header=None, dtype="int64")


# ---------------------------------------------------------------------------
# 1. Individual file: who lives in which family in each wave
# ---------------------------------------------------------------------------
# Variable names per wave, from the individual-file codebook.
wave_vars = {
    2017: dict(intnum="ER34501", seqno="ER34502", rel="ER34503", age="ER34504"),
    2019: dict(intnum="ER34701", seqno="ER34702", rel="ER34703", age="ER34704"),
    2021: dict(intnum="ER34901", seqno="ER34902", rel="ER34903", age="ER34904"),
    2023: dict(intnum="ER35101", seqno="ER35102", rel="ER35103", age="ER35104"),
}
wanted = ["ER30001", "ER30002", "ER32000"] + [v for w in WAVES for v in wave_vars[w].values()]

with zipfile.ZipFile(RAW / "ind2023er.zip") as zf:
    ind = read_fixed_width(zf, "ind2023er/IND2023ER.txt", "ind2023er/IND2023ER.do", wanted)

rename = {"ER30001": "id68", "ER30002": "pn", "ER32000": "sex"}
for w in WAVES:
    rename.update({code: f"{name}_{w}" for name, code in wave_vars[w].items()})
ind = ind.rename(columns=rename)
ind.to_csv(OUT / "individuals.csv", index=False)
print(f"individuals.csv   {len(ind):>7,} rows")

# ---------------------------------------------------------------------------
# 2. Family extract: labor income of reference person and spouse
# ---------------------------------------------------------------------------
# PSID Data Center spreadsheets carry a <sheetPr synchVertical=...> tag that recent
# versions of openpyxl reject, so drop that tag before handing the file to pandas.
with zipfile.ZipFile(RAW / "J366546.zip") as zf:
    xlsx = zf.read("J366546.xlsx")
src, buf = zipfile.ZipFile(io.BytesIO(xlsx)), io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as dst:
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename.startswith("xl/worksheets/"):
            data = re.sub(rb"<sheetPr[^>]*/>", b"", data)
        dst.writestr(item, data)
fam_wide = pd.read_excel(io.BytesIO(buf.getvalue()))

# In a family-only extract the columns for each wave are stacked side by side but the
# rows are NOT the same family across waves: row 5 in 2017 and row 5 in 2019 are
# unrelated. Each wave is cut out on its own; families are linked through the
# individual file later.
fam_vars = {
    2017: ("ER66002", "ER71293", "ER71321"),
    2019: ("ER72002", "ER77315", "ER77343"),
    2021: ("ER78002", "ER81642", "ER81670"),
    2023: ("ER82002", "ER85496", "ER85524"),
}
pieces = []
for w, (fid, rp, sp) in fam_vars.items():
    piece = (fam_wide[[fid, rp, sp]].dropna()
             .set_axis(["family_id", "rp_labor", "sp_labor"], axis=1)
             .astype("int64"))
    piece.insert(0, "survey_year", w)
    pieces.append(piece)
fam = pd.concat(pieces, ignore_index=True)
fam.to_csv(OUT / "family_income.csv", index=False)
print(f"family_income.csv {len(fam):>7,} rows")

# ---------------------------------------------------------------------------
# 3. Parent Identification File
# ---------------------------------------------------------------------------
pid_vars = ["PID2", "PID3", "PID4", "PID5", "PID23", "PID24"]
with zipfile.ZipFile(RAW / "pid23.zip") as zf:
    pid = read_fixed_width(zf, "PID23.txt", "PID23.do", pid_vars)
pid.columns = ["id68", "pn", "mother_id68", "mother_pn", "father_id68", "father_pn"]
pid.to_csv(OUT / "parents.csv", index=False)
print(f"parents.csv       {len(pid):>7,} rows")
