import sys
import subprocess
from pathlib import Path

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QTabWidget,
    QVBoxLayout, QHBoxLayout, QFormLayout,
    QPushButton, QFileDialog,
    QTextEdit, QPlainTextEdit,
    QLabel, QComboBox, QSplitter, QMessageBox,
    QSpinBox, QGroupBox, QLineEdit
)
from PyQt5.QtGui import (
    QSyntaxHighlighter, QTextCharFormat,
    QColor, QFont, QPixmap
)
from PyQt5.QtCore import Qt, QRegExp

try:
    import serial.tools.list_ports
    tiene_serial = True
except ImportError:
    tiene_serial = False

TEMAS = {
    "Classic": {
        "fondo_editor":  "#FFFFFF",
        "texto_editor":  "#000000",
        "fondo_consola": "#F0F0F0",
        "texto_consola": "#111111",
        "fondo_app":     "#DDDDDD",
        "qss_extra":     "",
        "tab_sel":       "#AAAAAA",
        "hl": {
            "instrucciones": "#7B00A0",
            "registros":     "#B85C00",
            "inmediatos":    "#0000CC",
            "etiquetas":     "#CC0000",
            "comentarios":   "#2A6000",
        },
    },
    "Dark": {
        "fondo_editor":  "#1E1E1E",
        "texto_editor":  "#D4D4D4",
        "fondo_consola": "#141414",
        "texto_consola": "#CCCCCC",
        "fondo_app":     "#252526",
        "qss_extra":     "background:#3C3C3C; color:#D4D4D4; border:1px solid #555;",
        "tab_sel":       "#555555",
        "hl": {
            "instrucciones": "#94018D",
            "registros":     "#FF9900",
            "inmediatos":    "#5599FF",
            "etiquetas":     "#FF4444",
            "comentarios":   "#4A9A1A",
        },
    },
    "PG Theme": {
        "fondo_editor":  "#1A001A",
        "texto_editor":  "#E0AAFF",
        "fondo_consola": "#0D000D",
        "texto_consola": "#CC99FF",
        "fondo_app":     "#2A0040",
        "qss_extra":     "background:#3D0060; color:#E0AAFF; border:1px solid #7B2FBE;",
        "tab_sel":       "#6A1B9A",
        "hl": {
            "instrucciones": "#FF66FF",
            "registros":     "#FFAA00",
            "inmediatos":    "#66AAFF",
            "etiquetas":     "#FF3366",
            "comentarios":   "#66BB44",
        },
    },
}


class ResaltadorAsm(QSyntaxHighlighter):
    def __init__(self, documento):
        super().__init__(documento)
        self.reglas = []
        self.recargar(TEMAS["Dark"]["hl"])

    def recargar(self, colores):
        self.reglas = []

        def hl(patron, clave, negrita=False):
            fmt = QTextCharFormat()
            fmt.setForeground(QColor(colores[clave]))
            if negrita:
                fmt.setFontWeight(QFont.Bold)
            self.reglas.append((QRegExp(patron, Qt.CaseInsensitive), fmt))

        hl(
            r"\b(ADDI|SUBI|ANDI|ORI|XORI|SLLI|SRLI|SLTI|"
            r"ADD|SUB|AND|OR|XOR|SLL|SRL|SLT|"
            r"LOAD|STORE|BEQ|JUMP|JAL|OUT|NOP|MOV)\b",
            "instrucciones", negrita=True
        )
        hl(r"\br[0-7]\b",                              "registros")
        hl(r"\b(0x[0-9a-fA-F]+|0b[01]+|-?\d+)\b",     "inmediatos")
        hl(r"^\s*\w+:",                                 "etiquetas")
        hl(r";[^\n]*",                                  "comentarios")
        self.rehighlight()

    def highlightBlock(self, texto):
        for patron, fmt in self.reglas:
            idx = patron.indexIn(texto)
            while idx >= 0:
                largo = patron.matchedLength()
                self.setFormat(idx, largo, fmt)
                idx = patron.indexIn(texto, idx + largo)

class PantallaWelcome(QWidget):
    def __init__(self):
        super().__init__()
        diseno = QVBoxLayout(self)
        diseno.setAlignment(Qt.AlignCenter)
        diseno.setSpacing(12)

        img_path = Path(__file__).parent / "imgs/i7.png" #logo
        if img_path.exists():
            lbl_img = QLabel()
            lbl_img.setPixmap(
                QPixmap(str(img_path)).scaled(300, 400, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            )
            lbl_img.setAlignment(Qt.AlignCenter)
            diseno.addWidget(lbl_img)

        titulo = QLabel("JoJoP IDE")
        titulo.setFont(QFont("Courier New", 28, QFont.Bold))
        titulo.setAlignment(Qt.AlignCenter)
        diseno.addWidget(titulo)

        subtitulo = QLabel("IDE de Risc V para MicroGT") #cambiar nombre
        subtitulo.setFont(QFont("Courier New", 13))
        subtitulo.setAlignment(Qt.AlignCenter)
        diseno.addWidget(subtitulo)

        creditos = QLabel(
            "Desarrollado por Pablo Jose Lopez Mazariegos.\n"
            "Hecho con amor y monster ultra\n"
            "Guatemala, 2026\n\n"
            "https://github.com/PabloJLM"
        )
        creditos.setFont(QFont("Courier New", 10))
        creditos.setAlignment(Qt.AlignCenter)
        diseno.addWidget(creditos)

class PestanaAjustes(QWidget):
    def __init__(self, ide):
        super().__init__()
        self.ide = ide
        diseno = QVBoxLayout(self)
        diseno.setAlignment(Qt.AlignTop)
        diseno.setSpacing(10)
        diseno.setContentsMargins(16, 16, 16, 16)

        grupo_ap = QGroupBox("Apariencia")
        forma_ap = QFormLayout(grupo_ap)

        self.combo_tema = QComboBox()
        self.combo_tema.addItems(TEMAS.keys())
        self.combo_tema.setCurrentText("Oscuro")
        self.combo_tema.currentTextChanged.connect(self.ide.aplicar_tema)
        forma_ap.addRow("Tema:", self.combo_tema)

        self.combo_fuente = QComboBox()
        self.combo_fuente.addItems(["Courier New", "Consolas", "Fira Code", "Monospace"])
        self.combo_fuente.currentTextChanged.connect(self.cambiar_fuente)
        forma_ap.addRow("Fuente:", self.combo_fuente)

        self.spin_tamanio = QSpinBox()
        self.spin_tamanio.setRange(8, 24)
        self.spin_tamanio.setValue(10)
        self.spin_tamanio.valueChanged.connect(self.cambiar_tamanio)
        forma_ap.addRow("Tamaño:", self.spin_tamanio)

        diseno.addWidget(grupo_ap)

        grupo_rutas = QGroupBox("Rutas de backend")
        forma_rutas = QFormLayout(grupo_rutas)

        self.campo_ensamblador = QLineEdit(self.ide.ruta_ensamblador)
        btn_ens = QPushButton("...")
        btn_ens.setFixedWidth(28)
        btn_ens.clicked.connect(lambda: self.elegir_ruta(self.campo_ensamblador))
        fila_ens = QHBoxLayout()
        fila_ens.addWidget(self.campo_ensamblador)
        fila_ens.addWidget(btn_ens)
        forma_rutas.addRow("assembler.py:", fila_ens)

        self.campo_flasher = QLineEdit(self.ide.ruta_flasher)
        btn_fl = QPushButton("...")
        btn_fl.setFixedWidth(28)
        btn_fl.clicked.connect(lambda: self.elegir_ruta(self.campo_flasher))
        fila_fl = QHBoxLayout()
        fila_fl.addWidget(self.campo_flasher)
        fila_fl.addWidget(btn_fl)
        forma_rutas.addRow("uart_flash.py:", fila_fl)

        btn_aplicar = QPushButton("Aplicar rutas")
        btn_aplicar.clicked.connect(self.aplicar_rutas)
        forma_rutas.addRow("", btn_aplicar)

        diseno.addWidget(grupo_rutas)
        diseno.addStretch()

    def elegir_ruta(self, campo):
        ruta, _ = QFileDialog.getOpenFileName(self, "Elegir script", "", "Python (*.py)")
        if ruta:
            campo.setText(ruta)

    def cambiar_fuente(self, nombre):
        tam = self.spin_tamanio.value()
        self.ide.editor.setFont(QFont(nombre, tam))
        self.ide.consola.setFont(QFont(nombre, tam - 1))

    def cambiar_tamanio(self, tam):
        nombre = self.combo_fuente.currentText()
        self.ide.editor.setFont(QFont(nombre, tam))
        self.ide.consola.setFont(QFont(nombre, tam - 1))

    def aplicar_rutas(self):
        self.ide.ruta_ensamblador = self.campo_ensamblador.text()
        self.ide.ruta_flasher     = self.campo_flasher.text()
        self.ide.escribir_consola("Rutas actualizadas.", "#4EC9B0")


class JoJoPIDE(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("JoJoP_IDE")
        self.resize(960, 680)
        self.archivo_actual   = None
        self.ruta_ensamblador = str(Path(__file__).parent / "tools" / "assembler.py")
        self.ruta_flasher     = str(Path(__file__).parent / "tools" / "uart_flash.py")
        self.construir_ui()
        self.aplicar_tema("Dark")#poner el default jsjs

    def construir_ui(self):
        self.pestanas = QTabWidget()
        self.setCentralWidget(self.pestanas)
        self.pestanas.addTab(PantallaWelcome(),    "Inicio")
        self.pestanas.addTab(self.crear_editor(),  "Editor")
        self.pestanas.addTab(PestanaAjustes(self), "Ajustes")

    def crear_editor(self):
        contenedor = QWidget()
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

        btn_bin = QPushButton("Compilar .bin")
        btn_bin.clicked.connect(self.compilar_bin)
        barra.addWidget(btn_bin)

        barra.addSpacing(12)

        barra.addWidget(QLabel("Puerto:"))
        self.selector_puerto = QComboBox()
        self.selector_puerto.setMinimumWidth(110)
        barra.addWidget(self.selector_puerto)

        btn_r = QPushButton("R")
        btn_r.setFixedWidth(26)
        btn_r.setToolTip("Refrescar puertos")
        btn_r.clicked.connect(self.get_puertos)
        barra.addWidget(btn_r)

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
        return contenedor

    def aplicar_tema(self, nombre):
        t = TEMAS.get(nombre, TEMAS["Dark"])

        self.editor.setStyleSheet(
            f"QPlainTextEdit {{ background:{t['fondo_editor']}; color:{t['texto_editor']}; }}"
        )
        self.consola.setStyleSheet(
            f"QTextEdit {{ background:{t['fondo_consola']}; color:{t['texto_consola']}; }}"
        )

        qss = f"QMainWindow, QWidget {{ background:{t['fondo_app']}; color:{t['texto_consola']}; }}"
        if t["qss_extra"]:
            q = t["qss_extra"]
            qss += (
                f" QPushButton {{ {q} border-radius:3px; padding:3px 8px; }}"
                f" QComboBox   {{ {q} }}"
                f" QSpinBox    {{ {q} }}"
                f" QLineEdit   {{ {q} }}"
                f" QGroupBox   {{ color:{t['texto_consola']}; }}"
                f" QTabBar::tab {{ {q} padding:5px 12px; }}"
                f" QTabBar::tab:selected {{ background:{t['tab_sel']}; color:white; }}"
            )
        self.setStyleSheet(qss)

        self.resaltador.recargar(t["hl"])

    # funciones aux

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

    # arcvhivos

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
            self.pestanas.setCurrentIndex(1)

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

    # compile

    def run_risc(self):
        origen = self.pedir_guardar()
        if not origen:
            return None
        bin_path = origen.with_suffix(".bin")
        comando = [
            sys.executable, self.ruta_ensamblador,
            str(origen),
            "-o", str(origen.with_suffix(".hex")),
            "--binary"
        ]
        self.escribir_consola(f"$ {' '.join(comando)}", "#569CD6")
        resultado = subprocess.run(comando, capture_output=True, text=True)
        if resultado.stdout:
            self.escribir_consola(resultado.stdout.strip())
        if resultado.stderr:
            self.escribir_consola(resultado.stderr.strip(), "#F44747")
        if resultado.returncode != 0:
            self.escribir_consola("FAIL", "#F44747")
            return None
        self.escribir_consola(f"OK  →  {bin_path}", "#4EC9B0")
        return bin_path

    def compilar_bin(self):
        self.run_risc()

    def get_puertos(self):
        self.selector_puerto.clear()
        if tiene_serial:
            for p in serial.tools.list_ports.comports():
                self.selector_puerto.addItem(p.device)
        if self.selector_puerto.count() == 0:
            self.selector_puerto.addItem("(ninguno)")

    def flashear(self):
        origen = self.pedir_guardar()
        if not origen:
            return
        bin_path = origen.with_suffix(".bin")
        if not bin_path.exists():
            self.escribir_consola("Sin .bin — compilando primero...", "#DCDCAA")
            if not self.run_risc():
                return
        puerto = self.selector_puerto.currentText()
        if not puerto or puerto == "(ninguno)":
            QMessageBox.warning(self, "Flash", "Selecciona un puerto serie.")
            return
        comando = [sys.executable, self.ruta_flasher, str(bin_path), "--port", puerto]
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
