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

@app.route('/stop-container', methods=['POST'])
def stop_container():
    data = request.get_json()
    match_id = data.get('match_id')

    if not match_id:
        return jsonify({'error': 'Match ID is required'}), 400

    try:
        # Find the container by name pattern matching the match_id
        # Assuming container names are like 'mirror-server-{match_id}.nakama1' or similar
        # Use a more specific filter based on the expected container name format
        list_cmd = f"docker ps -a --filter name=mirror-server-{match_id} -q"
        list_result = subprocess.run(list_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        if list_result.returncode != 0:
            return jsonify({'error': 'Failed to list containers', 'stderr': list_result.stderr.strip()}), 500

        container_ids = list_result.stdout.strip().split('\n')
        if not container_ids or container_ids[0] == '':
            return jsonify({'message': f'No containers found for match ID: {match_id}', 'list_stdout': list_result.stdout.strip(), 'list_stderr': list_result.stderr.strip()})

        # Assuming only one container per match ID
        target_container_id = container_ids[0]

        # Stop and remove the found container
        stop_cmd = f"docker stop {target_container_id}"
        stop_result = subprocess.run(stop_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        print(f"[DEBUG] Stop command: {stop_cmd}")
        print(f"[DEBUG] Stop stdout: {stop_result.stdout.strip()}")
        print(f"[DEBUG] Stop stderr: {stop_result.stderr.strip()}")
        print(f"[DEBUG] Stop returncode: {stop_result.returncode}")

        if stop_result.returncode != 0:
            return jsonify({'error': f'Failed to stop container {target_container_id}', 'stderr': stop_result.stderr.strip()}), 500

        remove_cmd = f"docker rm {target_container_id}"
        remove_result = subprocess.run(remove_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        print(f"[DEBUG] Remove command: {remove_cmd}")
        print(f"[DEBUG] Remove stdout: {remove_result.stdout.strip()}")
        print(f"[DEBUG] Remove stderr: {remove_result.stderr.strip()}")
        print(f"[DEBUG] Remove returncode: {remove_result.returncode}")

        if remove_result.returncode != 0:
            # Log error but don't necessarily return 500 if stop was successful
            print(f"[WARNING] Failed to remove container {target_container_id}: {remove_result.stderr.strip()}")

        return jsonify({
            'message': f'Container {target_container_id} associated with match ID {match_id} stopped and removed successfully',
            'container_id': target_container_id,
            'stop_stdout': stop_result.stdout.strip(),
            'stop_stderr': stop_result.stderr.strip(),
            'remove_stdout': remove_result.stdout.strip(),
            'remove_stderr': remove_result.stderr.strip()
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health')
def health_check():
    return jsonify({
        'status': 'healthy',
        'version': '1.0.5',
        'message': 'Another CI/CD test successful!'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

