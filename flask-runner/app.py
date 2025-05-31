from flask import Flask, request, jsonify
import subprocess
import json

app = Flask(__name__)

@app.route('/run-command', methods=['POST'])
def run_command():
    data = request.get_json()
    command = data.get('command')

    try:
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        response = {
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
        return jsonify(response)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

