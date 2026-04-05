#!/usr/bin/env python3
"""
============================================================================
MicroRV8-GT - UART Flash Tool
============================================================================
Carga un programa .bin (generado por assembler.py --binary) en la FPGA
via UART usando el protocolo del uart_loader.

Protocolo:
  TX -> 0xAA 0x55 [count_hi] [count_lo] [instr0_hi] [instr0_lo] ...

Requiere: pyserial
  pip install pyserial

Uso:
  python3 uart_flash.py programa.bin --port COM3
  python3 uart_flash.py programa.bin --port /dev/ttyUSB0
  python3 uart_flash.py --list        (listar puertos disponibles)
============================================================================
"""

import sys
import time
import argparse
from pathlib import Path

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("Error: pyserial no instalado.")
    print("  pip install pyserial")
    sys.exit(1)


BAUD_RATE = 115200
SYNC_HEADER = bytes([0xAA, 0x55])


def list_ports():
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("No se encontraron puertos serie.")
        return
    print("Puertos disponibles:")
    for p in ports:
        print(f"  {p.device:15} - {p.description}")


def load_bin(path: str) -> tuple[int, bytes]:
    """
    Lee archivo .bin generado por assembler.py --binary.
    Formato: 0xAA 0x55 count_hi count_lo [instrucciones...]
    Retorna (count, payload_sin_header)
    """
    data = Path(path).read_bytes()
    if len(data) < 4:
        raise ValueError("Archivo .bin demasiado corto")
    if data[0] != 0xAA or data[1] != 0x55:
        raise ValueError("Header invalido (esperado 0xAA 0x55)")
    count = ((data[2] & 0x01) << 8) | data[3]
    payload = data  # enviar completo incluyendo header
    return count, payload


def flash(port_name: str, bin_path: str, verbose: bool = True):
    count, payload = load_bin(bin_path)

    if verbose:
        print(f"Programa: {bin_path}")
        print(f"Instrucciones: {count}")
        print(f"Bytes a enviar: {len(payload)}")
        print(f"Puerto: {port_name} @ {BAUD_RATE} baud")

    with serial.Serial(port_name, BAUD_RATE, timeout=2) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        if verbose:
            print("Enviando...")

        ser.write(payload)
        ser.flush()

        # Esperar que el loader termine (tiempo estimado de transmision + margen)
        bytes_time = len(payload) * 10 / BAUD_RATE  # 10 bits por byte
        time.sleep(bytes_time + 0.5)

        if verbose:
            print("Listo. La FPGA deberia estar ejecutando el nuevo programa.")


def main():
    parser = argparse.ArgumentParser(
        description="MicroRV8-GT UART Flash Tool"
    )
    parser.add_argument("bin_file", nargs="?", help="Archivo .bin a cargar")
    parser.add_argument("--port", "-p", help="Puerto serie (ej: COM3, /dev/ttyUSB0)")
    parser.add_argument("--list", "-l", action="store_true",
                        help="Listar puertos disponibles")
    parser.add_argument("--quiet", "-q", action="store_true")
    args = parser.parse_args()

    if args.list:
        list_ports()
        return

    if not args.bin_file:
        parser.print_help()
        sys.exit(1)

    if not args.port:
        print("Error: especificar puerto con --port")
        list_ports()
        sys.exit(1)

    if not Path(args.bin_file).exists():
        print(f"Error: no se encontro '{args.bin_file}'")
        sys.exit(1)

    try:
        flash(args.port, args.bin_file, verbose=not args.quiet)
    except serial.SerialException as e:
        print(f"Error de puerto serie: {e}")
        sys.exit(1)
    except ValueError as e:
        print(f"Error en archivo: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
