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
            'stdout': result.stdout.strip(),
            'stderr': result.stderr.strip(),
            'returncode': result.returncode
        }
        return jsonify(response)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/stop-all-containers', methods=['POST'])
def stop_all_containers():
    try:
        # Önce tüm container'ları listele
        list_cmd = "docker ps -a --filter name=mirror-server- -q"
        list_result = subprocess.run(list_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        if list_result.returncode != 0:
            return jsonify({'error': 'Failed to list containers', 'stderr': list_result.stderr}), 500

        container_ids = list_result.stdout.strip().split('\n')
        if not container_ids or container_ids[0] == '':
            return jsonify({'message': 'No containers found', 'stopped': []})

        # Container'ları durdur ve sil
        stop_cmd = f"docker stop {' '.join(container_ids)} && docker rm {' '.join(container_ids)}"
        stop_result = subprocess.run(stop_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        if stop_result.returncode != 0:
            return jsonify({'error': 'Failed to stop containers', 'stderr': stop_result.stderr}), 500

        return jsonify({
            'message': 'Containers stopped and removed successfully',
            'stopped': container_ids,
            'stdout': stop_result.stdout.strip(),
            'stderr': stop_result.stderr.strip()
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health')
def health_check():
    return jsonify({
        'status': 'healthy',
        'version': '1.0.4',
        'message': 'Another CI/CD test successful!'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

