import tkinter as tk
from tkinter import filedialog, scrolledtext
import subprocess
import shutil
import sys
import os
import threading
import pathlib

# Si GTKWave no esta en PATH, configurar la ruta aqui:
# Windows: GTKWAVE_PATH = r"C:\gtkwave64\bin\gtkwave.exe"
GTKWAVE_PATH = None

# Orden de compilacion de los modulos del proyecto
PROJECT_FILES = [
    "alu.v",
    "regfile.v",
    "cpu_core.v",
    "instruction_memory.v",
    "data_memory.v",
    "gpio.v",
    "uart.v",
    "pwm.v",
    "uart_loader.v",
    "microrv8_system.v",
    "tang_nano_top.v",
]


def find_gtkwave():
    if GTKWAVE_PATH and pathlib.Path(GTKWAVE_PATH).exists():
        return GTKWAVE_PATH
    found = shutil.which("gtkwave")
    if found:
        return found
    for p in [r"C:\gtkwave64\bin\gtkwave.exe",
              r"C:\Program Files\GTKWave\bin\gtkwave.exe"]:
        if pathlib.Path(p).exists():
            return p
    return None


class SimGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("MicroRV8-GT Simulator")
        self.root.geometry("780x640")
        self.root.resizable(True, True)

        self.project_dir = tk.StringVar(value=str(pathlib.Path(__file__).parent))
        self.tb_file     = tk.StringVar()
        self.test_file   = tk.StringVar()
        self.top_module  = tk.StringVar()
        self.mode        = tk.IntVar(value=1)
        self.vvp_path    = None

        self.gtkwave_exe = find_gtkwave()
        self.iverilog_ok = bool(shutil.which("iverilog"))
        try:
            import cocotb_tools.runner
            self.cocotb_ok = True
        except ImportError:
            self.cocotb_ok = False

        self._build_ui()

    # ------------------------------------------------------------------ UI

    def _build_ui(self):
        P = {"padx": 8, "pady": 3}

        # Directorio
        f = tk.LabelFrame(self.root, text="Directorio del proyecto")
        f.pack(fill="x", **P)
        tk.Entry(f, textvariable=self.project_dir, width=70).pack(
            side="left", padx=4, pady=4)
        tk.Button(f, text="...", command=self._pick_dir, width=3).pack(side="left")

        # Modo
        fm = tk.LabelFrame(self.root, text="Modo de simulacion")
        fm.pack(fill="x", **P)
        tk.Radiobutton(fm,
            text="Testbench Verilog  —  iverilog + vvp + GTKWave",
            variable=self.mode, value=1,
            command=self._mode_changed).pack(anchor="w", padx=8, pady=2)
        tk.Radiobutton(fm,
            text="cocotb  —  Python directo, sin Make ni Makefile",
            variable=self.mode, value=2,
            command=self._mode_changed).pack(anchor="w", padx=8, pady=2)

        # Panel modo 1
        self.frm_v = tk.LabelFrame(self.root, text="Testbench .v")
        tk.Entry(self.frm_v, textvariable=self.tb_file, width=68).pack(
            side="left", padx=4, pady=4)
        tk.Button(self.frm_v, text="...", command=self._pick_tb, width=3
                  ).pack(side="left")

        # Panel modo 2
        self.frm_c = tk.LabelFrame(self.root, text="Test cocotb")
        r = tk.Frame(self.frm_c)
        r.pack(fill="x", padx=4, pady=4)
        tk.Label(r, text="Archivo .py:", width=12, anchor="w").grid(
            row=0, column=0, sticky="w")
        tk.Entry(r, textvariable=self.test_file, width=55).grid(
            row=0, column=1, padx=4)
        tk.Button(r, text="...", command=self._pick_test, width=3).grid(
            row=0, column=2)
        tk.Label(r, text="Top module:", width=12, anchor="w").grid(
            row=1, column=0, sticky="w", pady=(4,0))
        tk.Entry(r, textvariable=self.top_module, width=30).grid(
            row=1, column=1, sticky="w", padx=4, pady=(4,0))
        tk.Label(r, text="nombre del modulo Verilog DUT",
                 fg="gray").grid(row=1, column=1, sticky="e", padx=4)

        # Herramientas
        ft = tk.LabelFrame(self.root, text="Herramientas")
        ft.pack(fill="x", **P)
        self._status(ft, "iverilog", self.iverilog_ok)
        self._status(ft, "GTKWave",  bool(self.gtkwave_exe),
                     self.gtkwave_exe or "NO — ver 01_INSTALACION.md")
        self._status(ft, "cocotb",   self.cocotb_ok,
                     "OK" if self.cocotb_ok else "NO — pip install cocotb")

        # Botones
        fb = tk.Frame(self.root)
        fb.pack(fill="x", **P)
        btns = [
            ("Compilar",  self._compile,   "#1565C0"),
            ("Simular",   self._simulate,  "#2E7D32"),
            ("GTKWave",   self._gtkwave,   "#E65100"),
            ("Todo",      self._run_all,   "#6A1B9A"),
            ("Limpiar",   self._clear,     "#37474F"),
        ]
        for label, cmd, color in btns:
            tk.Button(fb, text=label, command=cmd, height=2,
                      bg=color, fg="white", font=("Arial", 10, "bold"),
                      activebackground=color, relief="flat"
                      ).pack(side="left", fill="x", expand=True, padx=2)

        # Log
        fl = tk.LabelFrame(self.root, text="Log")
        fl.pack(fill="both", expand=True, **P)
        self.log = scrolledtext.ScrolledText(
            fl, height=14, font=("Courier New", 9),
            bg="#1e1e1e", fg="#d4d4d4", insertbackground="white")
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

        self._mode_changed()

    def _status(self, parent, name, ok, text=None):
        t = text or ("OK" if ok else "NO ENCONTRADO")
        tk.Label(parent, text=f"  {name}: {t}",
                 fg="#2E7D32" if ok else "#B71C1C"
                 ).pack(side="left", padx=8)

    def _mode_changed(self):
        if self.mode.get() == 1:
            self.frm_c.pack_forget()
            self.frm_v.pack(fill="x", padx=8, pady=3, before=self.root.pack_slaves()[4])
        else:
            self.frm_v.pack_forget()
            self.frm_c.pack(fill="x", padx=8, pady=3, before=self.root.pack_slaves()[3])

    # ------------------------------------------------------------ Selectores

    def _pick_dir(self):
        d = filedialog.askdirectory(initialdir=self.project_dir.get())
        if d:
            self.project_dir.set(d)

    def _pick_tb(self):
        f = filedialog.askopenfilename(
            initialdir=self.project_dir.get(),
            filetypes=[("Verilog", "*.v")])
        if f:
            self.tb_file.set(f)

    def _pick_test(self):
        f = filedialog.askopenfilename(
            initialdir=self.project_dir.get(),
            filetypes=[("Python", "*.py")])
        if f:
            self.test_file.set(f)
            stem = pathlib.Path(f).stem
            if stem.startswith("test_") and not self.top_module.get():
                self.top_module.set(stem[5:])

    # ------------------------------------------------------------------ Log

    def _log(self, msg):
        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.root.update()

    def _log_safe(self, msg):
        """Loggear desde un hilo secundario."""
        self.root.after(0, self._log, msg)

    def _clear(self):
        self.log.delete("1.0", "end")

    # ---------------------------------------------------------- Archivos .v

    def _get_sources(self):
        proj = pathlib.Path(self.project_dir.get())
        out  = []
        for name in PROJECT_FILES:
            p = proj / name
            if p.exists():
                out.append(str(p))
            else:
                self._log(f"  AVISO: {name} no encontrado")
        return out

    # ------------------------------------------- Modo 1: Testbench Verilog

    def _compile(self):
        if self.mode.get() == 2:
            self._log("Modo cocotb: compilacion es automatica al simular.")
            return True
        return self._do_compile()

    def _do_compile(self):
        if not self.iverilog_ok:
            self._log("ERROR: iverilog no esta en PATH.")
            return False
        tb = self.tb_file.get()
        if not tb:
            self._log("ERROR: seleccionar un testbench .v")
            return False

        proj = pathlib.Path(self.project_dir.get())
        out  = str(proj / "output.vvp")
        cmd  = ["iverilog", "-g2012", "-o", out] + self._get_sources() + [tb]

        self._log(f"\n[COMPILAR]\n{' '.join(cmd)}\n")
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(proj))
        if r.stdout: self._log(r.stdout)
        if r.stderr: self._log(r.stderr)
        if r.returncode != 0:
            self._log("FAIL")
            return False
        self.vvp_path = out
        self._log(f"OK: {out}")
        return True

    def _simulate(self):
        if self.mode.get() == 2:
            return self._run_cocotb()
        return self._run_vvp()

    def _run_vvp(self):
        if not self.vvp_path or not pathlib.Path(self.vvp_path).exists():
            self._log("ERROR: compilar primero.")
            return False
        self._log(f"\n[SIMULAR]\nvvp {self.vvp_path}\n")
        r = subprocess.run(["vvp", self.vvp_path], capture_output=True, text=True,
                           cwd=str(pathlib.Path(self.vvp_path).parent))
        if r.stdout: self._log(r.stdout)
        if r.stderr: self._log(r.stderr)
        if r.returncode != 0:
            self._log("FAIL")
            return False
        self._log("OK: simulacion terminada.")
        return True

    def _gtkwave(self):
        if not self.gtkwave_exe:
            self._log(
                "ERROR: GTKWave no encontrado.\n"
                "  Windows: https://sourceforge.net/projects/gtkwave/files/\n"
                "  Linux:   sudo apt install gtkwave\n"
                "  Luego configurar GTKWAVE_PATH en sim_gui.py"
            )
            return
        proj = pathlib.Path(self.project_dir.get())
        vcds = sorted(proj.glob("*.vcd"),
                      key=lambda p: p.stat().st_mtime, reverse=True)
        if not vcds:
            self._log("ERROR: no hay .vcd. Simular primero.")
            return
        vcd = vcds[0]
        self._log(f"\n[GTKWAVE] {vcd}")
        subprocess.Popen([self.gtkwave_exe, str(vcd)])

    # -------------------------------------------- Modo 2: cocotb sin Make

    def _run_cocotb(self):
        if not self.cocotb_ok:
            self._log("ERROR: cocotb no instalado.\n  pip install cocotb")
            return False
        if not self.iverilog_ok:
            self._log("ERROR: iverilog no esta en PATH.")
            return False

        test_path = pathlib.Path(self.test_file.get())
        if not test_path.exists():
            self._log("ERROR: seleccionar un archivo .py")
            return False

        top = self.top_module.get().strip()
        if not top:
            self._log("ERROR: escribir el nombre del Top Module (modulo Verilog DUT)")
            return False

        self._log(f"\n[COCOTB]\n  DUT:  {top}\n  Test: {test_path}\n")
        threading.Thread(
            target=self._cocotb_thread,
            args=(test_path, top),
            daemon=True
        ).start()
        return True

    def _cocotb_thread(self, test_path, top):
        """
        Corre cocotb usando su Python API directamente.
        Esto es lo mismo que hace Make internamente, pero sin Make.

        Lo que hace cocotb_tools.runner.get_runner("icarus"):
          1. runner.build():
               - Escribe un archivo cocotb_iverilog_dump.v con un modulo auxiliar
               - Llama: iverilog -g2012 -s cocotb_iverilog_dump -o sim.vvp <fuentes>
          2. runner.test():
               - Setea las variables de entorno que cocotb necesita:
                   COCOTB_TOPLEVEL   = nombre del modulo DUT
                   COCOTB_TEST_MODULES = nombre del modulo Python de tests
                   LIBPYTHON_LOC     = ruta al .so de Python (para VPI)
                   PYTHONPATH        = rutas donde buscar el modulo de tests
               - Llama: vvp -M <libs_dir> -m libcocotbvpi_icarus sim.vvp
               - El VPI hook carga cocotb, que importa el modulo Python y corre los tests
        """
        try:
            from cocotb_tools.runner import get_runner

            proj      = pathlib.Path(self.project_dir.get())
            test_dir  = test_path.parent
            test_mod  = test_path.stem
            build_dir = proj / "sim_build" / test_mod

            # Fuentes: modulos del proyecto + cualquier .v en el directorio del test
            sources = [pathlib.Path(f) for f in self._get_sources_silent()]
            for extra in test_dir.glob("*.v"):
                if extra not in sources:
                    sources.append(extra)

            # El directorio del test tiene que estar en PYTHONPATH
            env = os.environ.copy()
            pypath = str(test_dir)
            if env.get("PYTHONPATH"):
                pypath += os.pathsep + env["PYTHONPATH"]
            env["PYTHONPATH"] = pypath

            runner = get_runner("icarus")

            self._log_safe(f"Compilando '{top}' con {len(sources)} archivo(s) fuente...")
            runner.build(
                verilog_sources=sources,
                hdl_toplevel=top,
                build_dir=str(build_dir),
                always=True,
                timescale=("1ns", "1ps"),
                extra_env=env,
            )

            self._log_safe(f"Ejecutando '{test_mod}'...")
            runner.test(
                hdl_toplevel=top,
                test_module=test_mod,
                build_dir=str(build_dir),
                extra_env=env,
            )

            self._log_safe("\nTests cocotb finalizados.")

        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 0
            if code == 0:
                self._log_safe("OK: todos los tests pasaron.")
            else:
                self._log_safe(f"FAIL: {code} test(s) fallaron.")
        except Exception as e:
            self._log_safe(f"ERROR: {e}")

    def _get_sources_silent(self):
        """Como _get_sources pero sin loggear advertencias (para usar desde hilo)."""
        proj = pathlib.Path(self.project_dir.get())
        return [str(proj / n) for n in PROJECT_FILES if (proj / n).exists()]

    def _run_all(self):
        if self.mode.get() == 1:
            if self._do_compile():
                if self._run_vvp():
                    self._gtkwave()
        else:
            self._run_cocotb()


if __name__ == "__main__":
    root = tk.Tk()
    SimGUI(root)
    root.mainloop()