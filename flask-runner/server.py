from flask import Flask, request
import subprocess

app = Flask(__name__)

@app.route('/run-command', methods=['POST'])
def run_command():
    data = request.json
    cmd = data.get("command")

    # Güvenlik filtresi
    if cmd not in ["ls -l", "uptime", "whoami"]:
        return {"error": "Komut izinli değil"}, 403

    result = subprocess.run(cmd.split(), capture_output=True, text=True)
    return {"output": result.stdout}

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000)
