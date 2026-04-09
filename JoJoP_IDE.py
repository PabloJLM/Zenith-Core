import sys
import subprocess
from pathlib import Path

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget,
    QVBoxLayout, QHBoxLayout,
    QPushButton, QFileDialog,
    QTextEdit, QPlainTextEdit,
    QLabel, QComboBox, QSplitter, QMessageBox
)
from PyQt5.QtGui import (
    QSyntaxHighlighter, QTextCharFormat,
    QColor, QFont
)
from PyQt5.QtCore import Qt, QRegExp

try:
    import serial.tools.list_ports
    tiene_serial = True
except ImportError:
    tiene_serial = False

ruta_ensamblador = str(Path(__file__).parent / "tools" / "assembler.py")
ruta_flasher     = str(Path(__file__).parent / "tools" / "uart_flash.py")


class ResaltadorAsm(QSyntaxHighlighter):
    def __init__(self, documento):
        super().__init__(documento)
        self.reglas = []

        def highlight(patron, color, negrita=False):
            formato = QTextCharFormat()
            formato.setForeground(QColor(color))
            if negrita:
                formato.setFontWeight(QFont.Bold)
            self.reglas.append((QRegExp(patron, Qt.CaseInsensitive), formato))

        instrucciones = (
            r"\b(ADDI|SUBI|ANDI|ORI|XORI|SLLI|SRLI|SLTI|"
            r"ADD|SUB|AND|OR|XOR|SLL|SRL|SLT|"
            r"LOAD|STORE|BEQ|JUMP|JAL|OUT|NOP|MOV)\b"
        )
        highlight(instrucciones,  "#94018D", negrita=True)#instrucciones de la ISA
        highlight(r"\br[0-7]\b",  "#FF9900")#registros
        highlight(r"\b(0x[0-9a-fA-F]+|0b[01]+|-?\d+)\b", "#1100FA")#IMMs
        highlight(r"^\s*\w+:",    "#FF0800")#rutinas xd
        highlight(r";[^\n]*",     "#23550C")#comentarios

    def highlightBlock(self, texto):
        for patron, formato in self.reglas:
            indice = patron.indexIn(texto)
            while indice >= 0:
                largo = patron.matchedLength()
                self.setFormat(indice, largo, formato)
                indice = patron.indexIn(texto, indice + largo)


class JoJoPIDE(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("JoJoP_IDE")
        self.resize(900, 640)
        self.archivo_actual = None
        self.construir_ui()

    def construir_ui(self):
        contenedor = QWidget()
        self.setCentralWidget(contenedor)
        diseno = QVBoxLayout(contenedor)
        diseno.setSpacing(4)
        diseno.setContentsMargins(6, 6, 6, 6)

        barra = QHBoxLayout()

        for etiqueta, accion in [
            ("Nuevo",        self.nuevo),
            ("Abrir",        self.abrir),
            ("Guardar",      self.guardar),
            ("Guardar como", self.guardar_como),
        ]:
            btn = QPushButton(etiqueta)
            btn.clicked.connect(accion)
            barra.addWidget(btn)

        barra.addSpacing(12)

        for etiqueta, accion in [
            ("Compilar .hex", self.compilar_hex),
            ("Compilar .bin", self.compilar_bin),
        ]:
            btn = QPushButton(etiqueta)
            btn.clicked.connect(accion)
            barra.addWidget(btn)

        barra.addSpacing(12)

        barra.addWidget(QLabel("Puerto:"))
        self.selector_puerto = QComboBox()
        self.selector_puerto.setMinimumWidth(110)
        barra.addWidget(self.selector_puerto)

        btn_refrescar = QPushButton("R")
        btn_refrescar.setFixedWidth(26)
        btn_refrescar.setToolTip("Refrescar puertos")
        btn_refrescar.clicked.connect(self.get_puertos)
        barra.addWidget(btn_refrescar)

        btn_flash = QPushButton("Flash")
        btn_flash.clicked.connect(self.flashear)
        barra.addWidget(btn_flash)

        barra.addStretch()
        diseno.addLayout(barra)

        divisor = QSplitter(Qt.Vertical)

        self.editor = QPlainTextEdit()
        self.editor.setFont(QFont("Courier New", 10))
        self.editor.setTabStopDistance(28)
        self.resaltador = ResaltadorAsm(self.editor.document())
        divisor.addWidget(self.editor)

        self.consola = QTextEdit()
        self.consola.setReadOnly(True)
        self.consola.setFont(QFont("Courier New", 9))
        self.consola.setMaximumHeight(160)
        divisor.addWidget(self.consola)

        divisor.setStretchFactor(0, 3)
        divisor.setStretchFactor(1, 1)
        diseno.addWidget(divisor)

        self.etiqueta_estado = QLabel("Listo")
        diseno.addWidget(self.etiqueta_estado)

        self.get_puertos()

    def escribir_consola(self, texto, color="#d4d4d4"):
        self.consola.append(f'<span style="color:{color}">{texto}</span>')

    def actualizar_estado(self, texto):
        self.etiqueta_estado.setText(texto)

    def pedir_guardar(self):
        if not self.archivo_actual:
            self.guardar_como()
        if not self.archivo_actual:
            return None
        self.guardar()
        return Path(self.archivo_actual)

    def nuevo(self):
        self.editor.clear()
        self.archivo_actual = None
        self.setWindowTitle("JoJoP_IDE")

    def abrir(self):
        ruta, _ = QFileDialog.getOpenFileName(
            self, "Abrir archivo", "", "Assembly (*.asm);;Todos (*)"
        )
        if ruta:
            self.archivo_actual = ruta
            self.editor.setPlainText(Path(ruta).read_text(encoding="utf-8"))
            self.setWindowTitle(f"JoJoP_IDE  —  {Path(ruta).name}")
            self.actualizar_estado(ruta)

    def guardar(self):
        if not self.archivo_actual:
            return self.guardar_como()
        Path(self.archivo_actual).write_text(
            self.editor.toPlainText(), encoding="utf-8"
        )
        self.actualizar_estado(f"Guardado: {self.archivo_actual}")

    def guardar_como(self):
        ruta, _ = QFileDialog.getSaveFileName(
            self, "Guardar como", "", "Assembly (*.asm);;Todos (*)"
        )
        if ruta:
            self.archivo_actual = ruta
            self.guardar()
            self.setWindowTitle(f"JoJoP_IDE  —  {Path(ruta).name}")

    def run_risc(self, argumentos_extra):
        origen = self.pedir_guardar()
        if not origen:
            return None
        salida = origen.with_suffix(".hex")
        comando = [sys.executable, ruta_ensamblador, str(origen), "-o", str(salida)] + argumentos_extra
        self.escribir_consola(f"$ {' '.join(comando)}", "#569CD6")
        resultado = subprocess.run(comando, capture_output=True, text=True)
        if resultado.stdout:
            self.escribir_consola(resultado.stdout.strip())
        if resultado.stderr:
            self.escribir_consola(resultado.stderr.strip(), "#F44747")
        if resultado.returncode != 0:
            self.escribir_consola("FAIL", "#F44747")
            return None
        self.escribir_consola("OK", "#4EC9B0")
        return salida

    def compilar_hex(self):
        self.run_risc([])

    def compilar_bin(self):
        salida = self.run_risc(["--binary"])
        if salida:
            self.escribir_consola(f"  bin: {salida.with_suffix('.bin')}", "#B5CEA8")

    def get_puertos(self):
        self.selector_puerto.clear()
        if tiene_serial:
            for puerto in serial.tools.list_ports.comports():
                self.selector_puerto.addItem(puerto.device)
        if self.selector_puerto.count() == 0:
            self.selector_puerto.addItem("(ninguno)")

    def flashear(self):
        origen = self.pedir_guardar()
        if not origen:
            return
        bin_path = origen.with_suffix(".bin")
        if not bin_path.exists():
            self.escribir_consola("No hay .bin, compilando primero...", "#DCDCAA")
            if not self.run_risc(["--binary"]):
                return
        puerto = self.selector_puerto.currentText()
        if not puerto or puerto == "(ninguno)":
            QMessageBox.warning(self, "Flash", "Selecciona un puerto serie.")
            return
        comando = [sys.executable, ruta_flasher, str(bin_path), "--port", puerto]
        self.escribir_consola(f"$ {' '.join(comando)}", "#569CD6")
        resultado = subprocess.run(comando, capture_output=True, text=True)
        if resultado.stdout:
            self.escribir_consola(resultado.stdout.strip())
        if resultado.stderr:
            self.escribir_consola(resultado.stderr.strip(), "#F44747")
        if resultado.returncode == 0:
            self.escribir_consola("Flash OK", "#4EC9B0")
        else:
            self.escribir_consola("Flash FAIL", "#F44747")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    ventana = JoJoPIDE()
    ventana.show()
    sys.exit(app.exec_())
