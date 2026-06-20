# rtmr2.py — RTMR2 全部源自 mkosi 产物 + 文档化常量
#   python3 rtmr2.py <shimx64.efi> <zeroseal.efi> <zeroseal.initrd>
import hashlib, struct, pefile, sys

X509_GUID      = bytes.fromhex("a159c0a5e494a74a87b5ab155c2bf072")   # UEFI 规范 EFI_CERT_X509_GUID
SHA256_GUID    = bytes.fromhex("2616c4c14c509240aca941f936934328")   # UEFI 规范 EFI_CERT_SHA256_GUID
SHIM_LOCK_GUID = bytes.fromhex("50ab5d6046e00043abb63dd810dd8b23")   # shim 源码 SHIM_LOCK_GUID

CCEL = {
    "MokList":        "053357ea65185f010b8caa1fc265cfd5e80c7cc781254fa3f1e5ea9d345a87003cf761472a2f0423f15297f55cfe248f",
    "MokListX":       "80ee2571334a57bf90238d21964447e542079d4805fa87887817a97dcb720906683a09b1ac634c76c0c0be1177f76110",
    "MokListTrusted": "8d2ce87d86f55fcfab770a047b090da23270fa206832dfea7e0c946fff451f819add242374be551b0d6318ed6c7d41d8",
    "LoadOptions":    "914d914a645fc37c4d2d50ddda67c039b5b78eba6946bb838b0b04fb1908dc378cb166b59aeb5da70dc914a7ae5c311e",
    "initrd":         "66b4763797e510fb9fcc0fc104b31644bde8b5ec33e347a61ba693146fd03e5277314beee2a3ce1e94971af0bb480305",
}

def sec(pe, name):
    data = bytes(pe.__data__)
    base = pe.FILE_HEADER.PointerToSymbolTable + pe.FILE_HEADER.NumberOfSymbols * 18
    for s in pe.sections:
        nm = s.Name.rstrip(b"\x00")
        if nm.startswith(b"/"):
            off = int(nm[1:]); nm = data[base + off:data.index(b"\x00", base + off)]
        if nm == name:
            return s.get_data()[:s.Misc_VirtualSize]
    raise KeyError(name)

def sha(b): return hashlib.sha384(b).hexdigest()
def sha_file(p):
    h = hashlib.sha384()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""): h.update(c)
    return h.hexdigest()
def esl(sigtype, owner, data):                # 组一个单条目 EFI_SIGNATURE_LIST
    sig = owner + data
    return sigtype + struct.pack("<III", 16 + 4 + 4 + 4 + len(sig), 0, len(sig)) + sig

shim, uki, initrd = sys.argv[1], sys.argv[2], sys.argv[3]

# MokList:从 shim .vendor_cert 的 vendor_authorized(裸证书)重建
vc = sec(pefile.PE(shim), b".vendor_cert")
auth_sz, _, auth_off, _ = struct.unpack_from("<IIII", vc, 0)
cert = vc[auth_off:auth_off + auth_sz]
moklist = sha(cert if cert[:16] == X509_GUID else esl(X509_GUID, SHIM_LOCK_GUID, cert))

# MokListX / MokListTrusted:shim 未 enroll 的固定默认
moklistx       = sha(esl(SHA256_GUID, SHIM_LOCK_GUID, b"\x00" * 32))   # 空占位:全零 sha256
moklisttrusted = sha(b"\x01")

# cmdline / initrd:UKI 与 initrd 产物
cmd = sec(pefile.PE(uki), b".cmdline").rstrip(b"\x00")
loadopts = sha(cmd.decode().encode("utf-16-le") + b"\x00\x00")
initrd_d = sha_file(initrd)

seq = [("MokList", moklist), ("MokListX", moklistx), ("MokListTrusted", moklisttrusted),
       ("LoadOptions", loadopts), ("initrd", initrd_d)]
r = b"\x00" * 48
for name, d in seq:
    print(f"{name:14s} {d}  {'OK' if d == CCEL[name] else '!! 不符'}")
    r = hashlib.sha384(r + bytes.fromhex(d)).digest()
print("RTMR2 =", r.hex())
