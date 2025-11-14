from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
redis_client = redis.StrictRedis(host='redis', port=6379, decode_responses=True)

# Initialize the vote counts
redis_client.setnx('dogs', 0)
redis_client.setnx('cats', 0)

@app.route('/vote', methods=['POST'])
def vote():
    data = request.json
    if not data or 'vote' not in data:
        return jsonify({'error': 'Invalid request'}), 400

    vote = data['vote'].lower()
    if vote not in ['dogs', 'cats']:
        return jsonify({'error': 'Invalid vote'}), 400

    redis_client.incr(vote)
    return jsonify({'message': f'Vote for {vote} recorded'})

@app.route('/results', methods=['GET'])
def results():
    return jsonify({
        'dogs': int(redis_client.get('dogs')),
        'cats': int(redis_client.get('cats'))
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
