import tkinter as tk
from tkinter import filedialog, messagebox
import subprocess
import os

class VerilogSimGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Tester jsjs")
        self.root.geometry("500x300")

        self.verilog_file = tk.StringVar()
        self.testbench_file = tk.StringVar()
        self.vvp_file = None

        self.build_ui()

    def build_ui(self):
        frame = tk.Frame(self.root, padx=20, pady=20)
        frame.pack(fill="both", expand=True)

        tk.Label(frame, text="Design .v file:").pack(anchor="w")
        tk.Entry(frame, textvariable=self.verilog_file, width=50).pack()
        tk.Button(frame, text="Buscar", command=self.select_verilog).pack(pady=5)

        tk.Label(frame, text="Testbench .v file:").pack(anchor="w", pady=(10,0))
        tk.Entry(frame, textvariable=self.testbench_file, width=50).pack()
        tk.Button(frame, text="Buscar", command=self.select_testbench).pack(pady=5)

        tk.Button(frame, text="Compilar (Icarus)", command=self.compile_verilog, height=2).pack(fill="x", pady=(20,5))
        tk.Button(frame, text="Run y Abrir GTKWave", command=self.run_and_open_wave, height=2).pack(fill="x")

    def select_verilog(self):
        file_path = filedialog.askopenfilename(filetypes=[("Verilog Files", "*.v")])
        if file_path:
            self.verilog_file.set(file_path)

    def select_testbench(self):
        file_path = filedialog.askopenfilename(filetypes=[("Verilog Files", "*.v")])
        if file_path:
            self.testbench_file.set(file_path)

    def compile_verilog(self):
        v_file = self.verilog_file.get()
        tb_file = self.testbench_file.get()

        if not v_file or not tb_file:
            messagebox.showerror("Error", "Selecciona ambos .v No sea pendejo daniel ")
            return

        output_name = os.path.join(os.path.dirname(v_file), "output.vvp")
        self.vvp_file = output_name

        try:
            cmd = ["iverilog", "-o", output_name, v_file, tb_file]
            subprocess.run(cmd, check=True)
            messagebox.showinfo("Success", f"Compilado!:\n{output_name}")
        except subprocess.CalledProcessError:
            messagebox.showerror("Compile Error", "Revisar el log xd .")

    def run_and_open_wave(self):
        if not self.vvp_file or not os.path.exists(self.vvp_file):
            messagebox.showerror("Error", "Compila antes...")
            return

        try:
            subprocess.run(["vvp", self.vvp_file], check=True)

            folder = os.path.dirname(self.vvp_file)
            vcd_path = None

            # Buscar recursivamente el primer VCD
            for root_dir, _, files in os.walk(folder):
                for f in files:
                    if f.lower().endswith(".vcd"):
                        vcd_path = os.path.join(root_dir, f)
                        break
                if vcd_path:
                    break

            if not vcd_path:
                messagebox.showwarning("No VCD", "No se encuentra el vcd")
                return

            print("VCD encontrado en:", vcd_path)
            subprocess.Popen(["gtkwave", vcd_path])

        except subprocess.CalledProcessError:
            messagebox.showerror("Runtime Error", "Ni idea rogale al de arriba")

if __name__ == "__main__":
    root = tk.Tk()
    app = VerilogSimGUI(root)
    root.mainloop()
