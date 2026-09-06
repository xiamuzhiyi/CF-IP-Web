# -*- coding: utf-8 -*-
"""CF 优选 IP 工具 - Web UI 后端 (Flask)

通过配置文件 + 非交互模式调用 SelectIP-port.ps1，
避免命令行直接传中文/Emoji 带来的编码问题。

启动: python web_ui.py [--port 5000] [--host 127.0.0.1]
"""
import json
import os
import re
import shutil
import subprocess
import threading
import time

from flask import Flask, jsonify, request, render_template, send_file

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PS_SCRIPT = os.path.join(BASE_DIR, "SelectIP-port.ps1")
CONFIG_PATH = os.path.join(BASE_DIR, "webui_config.json")
LOG_PATH = os.path.join(BASE_DIR, "webui_run.log")
RESULT_PATH = os.path.join(BASE_DIR, "result_formatted.txt")

app = Flask(__name__)
app.config["TEMPLATES_AUTO_RELOAD"] = True

_process = None
_log_file = None
_log_pos = 0
_utf8_tail = b""       # 上一轮读取末尾可能被截断的多字节字符
_lock = threading.Lock()
_log_lock = threading.Lock()
_status = {
    "state": "idle",          # idle | running | finished
    "pid": None,
    "exit_code": None,
    "started_at": None,
    "ended_at": None,
}


def find_powershell():
    for name in ("pwsh", "powershell"):
        path = shutil.which(name)
        if path:
            return path
    raise RuntimeError("未找到 PowerShell (pwsh 或 powershell)，请先安装。")


def _decode_utf8(data):
    """解码日志片段；若末尾多字节被截断，则保留给下一轮拼接。"""
    global _utf8_tail
    data = _utf8_tail + data
    if not data:
        return ""
    try:
        text = data.decode("utf-8")
        _utf8_tail = b""
        return text
    except UnicodeDecodeError as e:
        keep = len(data) - e.start
        if 0 < keep <= 3:
            text = data[:e.start].decode("utf-8", errors="replace")
            _utf8_tail = data[e.start:]
            return text
        _utf8_tail = b""
        return data.decode("utf-8", errors="replace")


def read_log_fragment():
    global _log_pos, _utf8_tail
    with _log_lock:
        if not os.path.exists(LOG_PATH):
            return ""
        size = os.path.getsize(LOG_PATH)
        if size <= _log_pos:
            return ""
        with open(LOG_PATH, "rb") as f:
            f.seek(_log_pos)
            data = f.read()
        _log_pos = size
    if not data:
        return ""
    if b"\x00" in data[:8]:
        return data.decode("utf-16-le", errors="replace")
    return _decode_utf8(data)


def watch_process(proc, logf):
    global _process, _log_file
    proc.wait()
    try:
        logf.close()
    except Exception:
        pass
    with _lock:
        if _process is proc:
            _process = None
            _log_file = None
        _status.update(state="finished", exit_code=proc.returncode, ended_at=time.time())


def build_ps_cmd(config_path, extra=None):
    ps = find_powershell()
    cmd = [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", PS_SCRIPT,
           "-ConfigFile", config_path, "-NonInteractive"]
    if extra:
        cmd += extra
    return cmd


def write_config(cfg, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def parse_ps1_defaults():
    """从 SelectIP-port.ps1 解析默认端口与内置测速源，供 Web UI 预填。"""
    result = {"port": 443, "sources": [], "parse_error": ""}
    if not os.path.exists(PS_SCRIPT):
        result["parse_error"] = "SelectIP-port.ps1 不存在"
        return result
    try:
        text = open(PS_SCRIPT, encoding="utf-8").read()
    except Exception as e:
        result["parse_error"] = str(e)
        return result

    m = re.search(r"\[int\]\$Port\s*=\s*(\d+)", text)
    if m:
        port = int(m.group(1))
        result["port"] = port if port > 0 else 443

    block = re.search(r"\$SpeedSources\s*=\s*@\((.*?)\)", text, re.S)
    if block:
        for item in re.finditer(
            r'\{\s*Name\s*=\s*"([^"]+)"[^}]*?Url\s*=\s*"([^"]+)"', block.group(1), re.S
        ):
            result["sources"].append({"name": item.group(1).strip(),
                                      "url": item.group(2).strip()})
    return result


@app.route("/api/ps1-defaults")
def api_ps1_defaults():
    return jsonify(parse_ps1_defaults())


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/start", methods=["POST"])
def api_start():
    global _process, _log_file, _log_pos, _utf8_tail
    cfg = request.get_json(silent=True)
    if not isinstance(cfg, dict):
        return jsonify({"ok": False, "error": "无效的配置数据。"}), 400

    with _lock:
        if _process is not None and _process.poll() is None:
            return jsonify({"ok": False, "error": "已有测速任务运行中，请先停止。"}), 409

        try:
            write_config(cfg, CONFIG_PATH)
        except Exception as e:
            return jsonify({"ok": False, "error": f"配置文件写入失败: {e}"}), 500

        try:
            logf = open(LOG_PATH, "wb", buffering=0)
        except Exception as e:
            return jsonify({"ok": False, "error": f"日志文件创建失败: {e}"}), 500
        _log_pos = 0
        _utf8_tail = b""

        try:
            proc = subprocess.Popen(
                build_ps_cmd(CONFIG_PATH),
                cwd=BASE_DIR,
                stdout=logf,
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
            )
        except Exception as e:
            logf.close()
            return jsonify({"ok": False, "error": f"测速任务启动失败: {e}"}), 500

        _process = proc
        _log_file = logf
        _status.update(state="running", pid=proc.pid, exit_code=None,
                       started_at=time.time(), ended_at=None)

    threading.Thread(target=watch_process, args=(proc, logf), daemon=True).start()
    return jsonify({"ok": True, "pid": proc.pid})


@app.route("/api/stop", methods=["POST"])
def api_stop():
    with _lock:
        proc = _process
    if proc is None or proc.poll() is not None:
        return jsonify({"ok": False, "error": "当前没有运行中的任务。"}), 400
    r = subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                       capture_output=True, timeout=30)
    # taskkill 的返回码不可靠（子进程竞争退出时报非 0），且 /F 终止是异步的，
    # 紧接着的 poll() 可能仍未翻转。以进程是否真正退出为准，宽限重查 3 秒。
    for _ in range(30):
        if proc.poll() is not None:
            break
        time.sleep(0.1)
    if proc.poll() is None:
        err = r.stderr.decode("gbk", errors="replace").strip() or f"taskkill 退出码 {r.returncode}"
        return jsonify({"ok": False, "error": f"停止任务失败: {err}"}), 500
    return jsonify({"ok": True})


@app.route("/api/status")
def api_status():
    global _status
    log = read_log_fragment()
    with _lock:
        proc = _process
        if proc is not None and proc.poll() is not None and _status["state"] == "running":
            _status.update(state="finished", exit_code=proc.returncode, ended_at=time.time())
        snapshot = dict(_status)
    snapshot["log"] = log
    return jsonify(snapshot)


@app.route("/api/result")
def api_result():
    if not os.path.exists(RESULT_PATH):
        return jsonify({"ok": False, "error": "结果文件尚未生成。"})
    with open(RESULT_PATH, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    return jsonify({"ok": True, "content": content})


@app.route("/api/result/download")
def api_result_download():
    if not os.path.exists(RESULT_PATH):
        return jsonify({"ok": False, "error": "结果文件尚未生成。"}), 404
    return send_file(RESULT_PATH, as_attachment=True, download_name="result_formatted.txt")


@app.route("/api/dryrun", methods=["POST"])
def api_dryrun():
    cfg = request.get_json(silent=True)
    if not isinstance(cfg, dict):
        return jsonify({"ok": False, "error": "无效的配置数据。"}), 400
    tmp = os.path.join(BASE_DIR, "webui_config.dryrun.json")
    try:
        write_config(cfg, tmp)
    except Exception as e:
        return jsonify({"ok": False, "error": f"配置文件写入失败: {e}"}), 500
    try:
        r = subprocess.run(build_ps_cmd(tmp, ["-DryRun"]), cwd=BASE_DIR,
                           capture_output=True, timeout=120)
    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "error": "配置校验超时。"}), 500
    out = r.stdout.decode("utf-8", errors="replace")
    if not out:
        out = r.stderr.decode("utf-8", errors="replace")
    return jsonify({"ok": r.returncode == 0, "exit_code": r.returncode, "output": out})


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="CF 优选 IP Web UI")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5000)
    args = ap.parse_args()
    print("=" * 50)
    print("  CF 优选 IP Web UI 已启动")
    print(f"  访问地址: http://{args.host}:{args.port}")
    print("  按 Ctrl+C 退出")
    print("=" * 50)
    app.run(host=args.host, port=args.port, debug=False, threaded=True)
