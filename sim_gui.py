#!/usr/bin/env python3
"""
============================================================================
MicroRV8-GT - Simulation GUI
============================================================================
Herramienta grafica para compilar y simular con Icarus Verilog + GTKWave.

Requiere:
  - Python 3.8+
  - Icarus Verilog (iverilog, vvp) en PATH
  - GTKWave en PATH o ruta configurada abajo

Uso:
  python3 sim_gui.py
============================================================================
"""

import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext
import subprocess
import os
import sys
import shutil
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuracion: ajustar si GTKWave no esta en PATH
# ---------------------------------------------------------------------------
# Windows: descargar desde https://sourceforge.net/projects/gtkwave/
# Extraer y apuntar GTKWAVE_PATH al ejecutable gtkwave.exe
# Ejemplo:
#   GTKWAVE_PATH = r"C:\gtkwave64\bin\gtkwave.exe"
# Dejar en None para buscar en PATH automaticamente
GTKWAVE_PATH = None

# Archivos del proyecto (en orden de compilacion)
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
]

# ---------------------------------------------------------------------------
# Logica auxiliar
# ---------------------------------------------------------------------------

def find_gtkwave() -> str | None:
    if GTKWAVE_PATH and Path(GTKWAVE_PATH).exists():
        return GTKWAVE_PATH
    found = shutil.which("gtkwave")
    if found:
        return found
    # Rutas comunes en Windows
    common_win = [
        r"C:\gtkwave64\bin\gtkwave.exe",
        r"C:\Program Files\GTKWave\bin\gtkwave.exe",
        r"C:\gtkwave\bin\gtkwave.exe",
    ]
    for p in common_win:
        if Path(p).exists():
            return p
    return None


def find_tool(name: str) -> str | None:
    return shutil.which(name)


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------

class SimGUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("MicroRV8-GT Simulator")
        self.root.geometry("700x550")
        self.root.resizable(True, True)

        self.project_dir = tk.StringVar(value=str(Path(__file__).parent))
        self.tb_file     = tk.StringVar()
        self.extra_files = tk.StringVar()  # archivos .v adicionales separados por coma
        self.vvp_path    = None

        self._check_tools()
        self._build_ui()

    def _check_tools(self):
        self.iverilog_ok = find_tool("iverilog") is not None
        self.vvp_ok      = find_tool("vvp") is not None
        self.gtkwave_exe = find_gtkwave()

    def _build_ui(self):
        pad = {"padx": 8, "pady": 4}

        # -- Directorio del proyecto --
        frm_dir = tk.LabelFrame(self.root, text="Directorio del proyecto")
        frm_dir.pack(fill="x", **pad)
        tk.Entry(frm_dir, textvariable=self.project_dir, width=70).pack(
            side="left", padx=4, pady=4)
        tk.Button(frm_dir, text="Buscar",
                  command=self._select_dir).pack(side="left", padx=4)

        # -- Testbench --
        frm_tb = tk.LabelFrame(self.root, text="Testbench (.v)")
        frm_tb.pack(fill="x", **pad)
        tk.Entry(frm_tb, textvariable=self.tb_file, width=70).pack(
            side="left", padx=4, pady=4)
        tk.Button(frm_tb, text="Buscar",
                  command=self._select_tb).pack(side="left", padx=4)

        # -- Archivos extra --
        frm_extra = tk.LabelFrame(self.root, text="Archivos .v adicionales (opcional, separar con coma)")
        frm_extra.pack(fill="x", **pad)
        tk.Entry(frm_extra, textvariable=self.extra_files, width=70).pack(
            padx=4, pady=4, fill="x")

        # -- Estado de herramientas --
        frm_tools = tk.LabelFrame(self.root, text="Estado de herramientas")
        frm_tools.pack(fill="x", **pad)
        iv_color  = "green" if self.iverilog_ok else "red"
        vvp_color = "green" if self.vvp_ok else "red"
        gtk_color = "green" if self.gtkwave_exe else "orange"
        tk.Label(frm_tools, text=f"iverilog: {'OK' if self.iverilog_ok else 'NO ENCONTRADO'}",
                 fg=iv_color).pack(side="left", padx=8)
        tk.Label(frm_tools, text=f"vvp: {'OK' if self.vvp_ok else 'NO ENCONTRADO'}",
                 fg=vvp_color).pack(side="left", padx=8)
        gtk_txt = self.gtkwave_exe if self.gtkwave_exe else "NO ENCONTRADO"
        tk.Label(frm_tools, text=f"gtkwave: {gtk_txt}", fg=gtk_color,
                 wraplength=400, justify="left").pack(side="left", padx=8)

        # -- Botones de accion --
        frm_btn = tk.Frame(self.root)
        frm_btn.pack(fill="x", **pad)
        tk.Button(frm_btn, text="1. Compilar (iverilog)", height=2,
                  command=self._compile, bg="#2196F3", fg="white",
                  font=("Arial", 10, "bold")).pack(side="left", fill="x",
                  expand=True, padx=2)
        tk.Button(frm_btn, text="2. Simular (vvp)", height=2,
                  command=self._simulate, bg="#4CAF50", fg="white",
                  font=("Arial", 10, "bold")).pack(side="left", fill="x",
                  expand=True, padx=2)
        tk.Button(frm_btn, text="3. Abrir GTKWave", height=2,
                  command=self._open_gtkwave, bg="#FF9800", fg="white",
                  font=("Arial", 10, "bold")).pack(side="left", fill="x",
                  expand=True, padx=2)
        tk.Button(frm_btn, text="Todo en uno", height=2,
                  command=self._run_all, bg="#9C27B0", fg="white",
                  font=("Arial", 10, "bold")).pack(side="left", fill="x",
                  expand=True, padx=2)

        # -- Log --
        frm_log = tk.LabelFrame(self.root, text="Log")
        frm_log.pack(fill="both", expand=True, **pad)
        self.log = scrolledtext.ScrolledText(frm_log, height=12, font=("Courier", 9))
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

    # -- Callbacks --

    def _select_dir(self):
        d = filedialog.askdirectory()
        if d:
            self.project_dir.set(d)

    def _select_tb(self):
        f = filedialog.askopenfilename(
            initialdir=self.project_dir.get(),
            filetypes=[("Verilog", "*.v")])
        if f:
            self.tb_file.set(f)

    def _log(self, msg: str):
        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.root.update()

    def _get_project_files(self) -> list[str]:
        """Obtiene lista completa de archivos .v del proyecto."""
        proj_dir = Path(self.project_dir.get())
        files = []
        for name in PROJECT_FILES:
            p = proj_dir / name
            if p.exists():
                files.append(str(p))
            else:
                self._log(f"  AVISO: no encontrado {name}")

        # Archivos extra
        extras = self.extra_files.get().strip()
        if extras:
            for e in extras.split(","):
                e = e.strip()
                if e:
                    files.append(e)
        return files

    def _compile(self) -> bool:
        if not self.iverilog_ok:
            messagebox.showerror("Error", "iverilog no encontrado en PATH.\n"
                                 "Instalar desde: https://bleyer.org/icarus/")
            return False

        tb = self.tb_file.get()
        if not tb:
            messagebox.showerror("Error", "Selecciona un archivo testbench.")
            return False

        proj_dir = Path(self.project_dir.get())
        out_vvp  = str(proj_dir / "output.vvp")

        src_files = self._get_project_files()
        src_files.append(tb)

        cmd = ["iverilog", "-g2012", "-o", out_vvp] + src_files

        self._log(f"\n[COMPILAR] {' '.join(cmd)}\n")
        try:
            result = subprocess.run(cmd, capture_output=True, text=True,
                                    cwd=str(proj_dir))
            if result.stdout:
                self._log(result.stdout)
            if result.stderr:
                self._log(result.stderr)

            if result.returncode != 0:
                self._log("ERROR: compilacion fallida.")
                return False

            self.vvp_path = out_vvp
            self._log(f"OK: compilado -> {out_vvp}")
            return True

        except FileNotFoundError:
            self._log("ERROR: iverilog no encontrado.")
            return False

    def _simulate(self) -> bool:
        if not self.vvp_path or not Path(self.vvp_path).exists():
            messagebox.showerror("Error", "Compilar primero.")
            return False

        self._log(f"\n[SIMULAR] vvp {self.vvp_path}\n")
        try:
            result = subprocess.run(["vvp", self.vvp_path],
                                    capture_output=True, text=True,
                                    cwd=str(Path(self.vvp_path).parent))
            if result.stdout:
                self._log(result.stdout)
            if result.stderr:
                self._log(result.stderr)

            if result.returncode != 0:
                self._log("ERROR: simulacion fallida.")
                return False

            self._log("OK: simulacion terminada.")
            return True

        except FileNotFoundError:
            self._log("ERROR: vvp no encontrado.")
            return False

    def _open_gtkwave(self):
        if not self.gtkwave_exe:
            messagebox.showerror(
                "GTKWave no encontrado",
                "Descargar GTKWave desde:\n"
                "https://sourceforge.net/projects/gtkwave/files/\n\n"
                "Windows: descargar gtkwave64-x.x.x-bin-win64.zip\n"
                "Extraer y editar GTKWAVE_PATH en sim_gui.py\n"
                "o agregar la carpeta bin/ al PATH del sistema."
            )
            return

        # Buscar .vcd en directorio del proyecto
        proj_dir = Path(self.vvp_path).parent if self.vvp_path else Path(self.project_dir.get())
        vcd_files = list(proj_dir.glob("*.vcd"))

        if not vcd_files:
            messagebox.showwarning("Sin VCD",
                                   "No se encontro archivo .vcd.\n"
                                   "Ejecutar la simulacion primero.")
            return

        # Usar el .vcd mas reciente
        vcd = max(vcd_files, key=lambda p: p.stat().st_mtime)
        self._log(f"\n[GTKWAVE] Abriendo {vcd}\n")
        subprocess.Popen([self.gtkwave_exe, str(vcd)])

    def _run_all(self):
        if self._compile():
            if self._simulate():
                self._open_gtkwave()


def main():
    root = tk.Tk()
    app = SimGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
