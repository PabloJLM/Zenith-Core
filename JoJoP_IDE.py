import sys
import json
import subprocess
from pathlib import Path

from PyQt5.QtCore import Qt, QRegExp
from PyQt5.QtGui import QColor, QFont, QPixmap, QTextCharFormat, QSyntaxHighlighter
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QTabWidget,
    QVBoxLayout, QHBoxLayout, QFormLayout,
    QPushButton, QFileDialog, QTextEdit, QPlainTextEdit,
    QLabel, QComboBox, QSplitter, QMessageBox,
    QSpinBox, QGroupBox, QLineEdit
)

try:
    import serial.tools.list_ports
    tiene_serial = True
except ImportError:
    tiene_serial = False

# Temas -----------------------------------------
# Se cargan desde temas.json (mismo directorio que este script)
# Estructura: { "Categoría": { "Nombre": { ...datos... } } }
# Para agregar un tema nuevo: solo editar temas.json, sin tocar este archivo

_TEMAS_PATH = Path(__file__).parent / "temas.json"

def cargar_temas() -> dict:
    with _TEMAS_PATH.open(encoding="utf-8") as f:
        return json.load(f)

TEMAS: dict = cargar_temas()

def buscar_tema(nombre: str) -> dict:
    # busca el tema por nombre en todas las categorias
    for categoria in TEMAS.values():
        if nombre in categoria:
            return categoria[nombre]
    return TEMAS["Básicos"]["Dark"]  # fallback


class ResaltadorAsm(QSyntaxHighlighter):
    def __init__(self, documento):
        super().__init__(documento)  # inicia lo que resalta el ide de sintaxis
        self.reglas = []
        self.recargar(TEMAS["Básicos"]["Dark"]["hl"])  # color oscuro al iniciar

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
        )  # reglas de regex y formato
        hl(r"\br[0-7]\b",                              "registros")
        hl(r"\b(0x[0-9a-fA-F]+|0b[01]+|-?\d+)\b",     "inmediatos")
        hl(r"^\s*\w+:",                                 "etiquetas")
        hl(r";[^\n]*",                                  "comentarios")
        self.rehighlight()

    def highlightBlock(self, texto):  # busca en todo el documento y pone colores highlight
        for patron, fmt in self.reglas:
            idx = patron.indexIn(texto)
            while idx >= 0:
                largo = patron.matchedLength()
                self.setFormat(idx, largo, fmt)
                idx = patron.indexIn(texto, idx + largo)


class PantallaWelcome(QWidget):  # pantalla inicial del IDE
    def __init__(self):
        super().__init__()
        diseno = QVBoxLayout(self)
        diseno.setAlignment(Qt.AlignCenter)
        diseno.setSpacing(12)

        img_path = Path(__file__).parent / "imgs/resee.jpeg"  # imagen inicial igual inicia si hay o no xd
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

        subtitulo = QLabel("IDE de Risc V para MicroGT")  # ¿cambiar nombre?
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
    def __init__(self, ide):  # configura el panel con tema fuente tamaño y rutas
        super().__init__()
        self.ide = ide
        diseno = QVBoxLayout(self)
        diseno.setAlignment(Qt.AlignTop)
        diseno.setSpacing(10)
        diseno.setContentsMargins(16, 16, 16, 16)

        grupo_ap = QGroupBox("Apariencia")
        forma_ap = QFormLayout(grupo_ap)

        # combo con categorias como headers no seleccionables
        self.combo_tema = QComboBox()
        for cat, temas in TEMAS.items():
            # header de categoria (no seleccionable, gris, italica)
            self.combo_tema.addItem(f"── {cat} ──")
            idx = self.combo_tema.count() - 1
            item = self.combo_tema.model().item(idx)
            item.setFlags(Qt.NoItemFlags)
            item.setForeground(QColor("#888888"))
            font_h = QFont()
            font_h.setItalic(True)
            item.setFont(font_h)
            # temas de la categoria con indentacion visual
            for nombre in temas:
                self.combo_tema.addItem(f"  {nombre}")

        self.combo_tema.setCurrentText("  Dark")
        self.combo_tema.currentTextChanged.connect(
            lambda txt: self.ide.aplicar_tema(txt.strip())
        )
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

        grupo_rutas = QGroupBox("Rutas de asm")
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

    def elegir_ruta(self, campo):  # abre un dialogo y la guarda (busca archivos .py)
        ruta, _ = QFileDialog.getOpenFileName(self, "Elegir script", "", "Python (*.py)")
        if ruta:
            campo.setText(ruta)

    def cambiar_fuente(self, nombre):  # cambia la fuente del ide y consola
        tam = self.spin_tamanio.value()
        self.ide.editor.setFont(QFont(nombre, tam))
        self.ide.consola.setFont(QFont(nombre, tam - 1))

    def cambiar_tamanio(self, tam):  # cambia el tamaño de la fuente, la consola siempre es mas pequeña
        nombre = self.combo_fuente.currentText()
        self.ide.editor.setFont(QFont(nombre, tam))
        self.ide.consola.setFont(QFont(nombre, tam - 1))

    def aplicar_rutas(self):  # guarda las rutas de assembler.py y flasher uart
        self.ide.ruta_ensamblador = self.campo_ensamblador.text()
        self.ide.ruta_flasher     = self.campo_flasher.text()
        self.ide.escribir_consola("Rutas actualizadas.", "#4EC9B0")


class JoJoPIDE(QMainWindow):  # ventana principal
    def __init__(self):  # añade titulo, tamaño y rutas por defecto
        super().__init__()
        self.setWindowTitle("JoJoP_IDE")
        self.resize(960, 680)
        self.archivo_actual   = None
        self.ruta_ensamblador = str(Path(__file__).parent / "tools" / "assembler.py")
        self.ruta_flasher     = str(Path(__file__).parent / "tools" / "uart_flash.py")
        self.construir_ui()
        self.aplicar_tema("Dark")  # poner el default jsjs

    def construir_ui(self):  # crea las pestañas de arriba
        self.pestanas = QTabWidget()
        self.setCentralWidget(self.pestanas)
        self.pestanas.addTab(PantallaWelcome(),    "Inicio")
        self.pestanas.addTab(self.crear_editor(),  "Editor")
        self.pestanas.addTab(PestanaAjustes(self), "Ajustes")

    def crear_editor(self):  # pone la barra, selector de puerto, editor de texto, consola
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

    def aplicar_tema(self, nombre):  # aplica los temas segun elegidos por default esta dark
        t = buscar_tema(nombre)

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

    # funciones

    def escribir_consola(self, texto, color="#d4d4d4"):  # texto en la consola xd
        self.consola.append(f'<span style="color:{color}">{texto}</span>')

    def actualizar_estado(self, texto):  # actualiza el label de estado abajo
        self.etiqueta_estado.setText(texto)

    def pedir_guardar(self):  # salta opcion de guardar sino hay archivo
        if not self.archivo_actual:
            self.guardar_como()
        if not self.archivo_actual:
            return None
        self.guardar()
        return Path(self.archivo_actual)

    # archivos

    def nuevo(self):  # limpia el editor y borra el texto actual
        self.editor.clear()
        self.archivo_actual = None
        self.setWindowTitle("JoJoP_IDE")

    def abrir(self):  # abre archivos buscando .asm y lo carga en el editor
        ruta, _ = QFileDialog.getOpenFileName(
            self, "Abrir archivo", "", "Assembly (*.asm);;Todos (*)"
        )
        if ruta:
            self.archivo_actual = ruta
            self.editor.setPlainText(Path(ruta).read_text(encoding="utf-8"))
            self.setWindowTitle(f"JoJoP_IDE  —  {Path(ruta).name}")
            self.actualizar_estado(ruta)
            self.pestanas.setCurrentIndex(1)

    def guardar(self):  # guarda el contenido actual xd
        if not self.archivo_actual:
            return self.guardar_como()
        Path(self.archivo_actual).write_text(
            self.editor.toPlainText(), encoding="utf-8"
        )
        self.actualizar_estado(f"Guardado: {self.archivo_actual}")

    def guardar_como(self):  # guarda el archivo como el nombre que se quiere
        ruta, _ = QFileDialog.getSaveFileName(
            self, "Guardar como", "", "Assembly (*.asm);;Todos (*)"
        )
        if ruta:
            self.archivo_actual = ruta
            self.guardar()
            self.setWindowTitle(f"JoJoP_IDE  —  {Path(ruta).name}")

    # compile

    def run_risc(self):  # guarda archivo - ejecuta assembler como sub proceso - genera el binario - muestra el output
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

    def compilar_bin(self):  # llama a la funcion run risc (arriba)
        self.run_risc()

    def get_puertos(self):  # lista los puertos seriales disponibles con pyserial
        self.selector_puerto.clear()
        if tiene_serial:
            for p in serial.tools.list_ports.comports():
                self.selector_puerto.addItem(p.device)
        if self.selector_puerto.count() == 0:
            self.selector_puerto.addItem("(ninguno)")

    def flashear(self):  # verifica si existe .bin - sino hay compila el actual - ejecuta el flasher - muestra estado si se carga
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


if __name__ == "__main__":  # inicializador de la gui
    app = QApplication(sys.argv)
    ventana = JoJoPIDE()
    ventana.show()
    sys.exit(app.exec_())