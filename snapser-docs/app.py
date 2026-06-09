'''
AI Based Service for Docs Search and Snapser Cortex
'''
import os
import json
import time
import shutil
import requests
from typing import Union
from flask import Flask, request, jsonify
from openai import OpenAI
from openai.types import CreateEmbeddingResponse
from annoy import AnnoyIndex
from sentence_transformers import SentenceTransformer
from clone_repo import clone, delete_clone
from feature_extractor import scan_and_extract, detect_primary_language
from detect_project import detect_project_type
from openai_wrapper import summarize_project_name, analyze_snapend_logs, analyze_business_metrics
from anthropic_wrapper import update_snapser_manager_ts, generate_new_snapser_manager_ts


app = Flask(__name__)

# ── Embedding provider config ──────────────────────────────────────────
# Set EMBEDDING_PROVIDER=openai to switch back to OpenAI embeddings
EMBEDDING_PROVIDER = os.getenv('EMBEDDING_PROVIDER', 'local')  # 'local' or 'openai'
LOCAL_MODEL_NAME = 'all-MiniLM-L6-v2'  # 384 dimensions, ~80MB, runs on CPU
EMBEDDING_DIMENSIONS = 384 if EMBEDDING_PROVIDER == 'local' else 1536

annoy_index = None  # Global variable to hold the Annoy index
lookup = None  # Global variable to hold the lookup table
local_model = None  # Global variable to hold the local embedding model
# tokenizer = BertTokenizer.from_pretrained('bert-base-uncased') # Load the BERT tokenizer
# model = BertModel.from_pretrained('bert-base-uncased') # Load the BERT model


def load_local_model():
    '''
    Load the local sentence-transformers model into memory (once at startup).
    Only loads if EMBEDDING_PROVIDER is set to 'local'.
    '''
    global local_model
    if EMBEDDING_PROVIDER == 'local':
        print(f"Loading local embedding model: {LOCAL_MODEL_NAME}...")
        local_model = SentenceTransformer(LOCAL_MODEL_NAME)
        print("Local embedding model loaded successfully.")
    else:
        print("Using OpenAI for embeddings (local model not loaded).")


def load_annoy_index():
    global annoy_index
    # f = 768  # Set this to the dimensionality of your embeddings
    # f = 1536  # OpenAi uses 1536 dimensions
    f = EMBEDDING_DIMENSIONS  # Matches the embedding provider's output dimensions
    annoy_index = AnnoyIndex(f, 'angular')
    annoy_index.load('snapser-search.ann')  # Ensure this path is correct
    print(f"Annoy index loaded successfully (dimensions: {f}).")


def load_lookup():
    global lookup
    try:
        with open('snapser-search.json') as f:
            lookup = json.load(f)
        print("Lookup table loaded successfully.")
    except Exception as e:
        print(f"Failed to load lookup table: {str(e)}")
        lookup = {}  # Default to an empty dictionary in case of failure


with app.app_context():
    load_local_model()
    load_annoy_index()
    load_lookup()

# def text_to_embedding(text):
#     '''
#     Convert text to an embedding using BERT
#     '''
#     # Tokenize the input text and convert to tensor
#     inputs = tokenizer(text, return_tensors="pt",
#                        padding=True, truncation=True)

#     # Forward pass, get hidden states
#     with torch.no_grad():
#         outputs = model(**inputs)

#     # Use the mean of the last hidden state as the sentence embedding
#     embeddings = outputs.last_hidden_state.mean(dim=1).squeeze().numpy()
#     return embeddings


def text_to_embedding_oai(text: str) -> Union[list, None]:
    '''
    Convert text to an embedding using OpenAI's text-embedding-ada-002 model.
    Returns a 1536-dimensional vector. Requires OPENAI_API_KEY env var.
    '''
    client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
    response: CreateEmbeddingResponse = client.embeddings.create(
        input=text,
        model="text-embedding-ada-002"
    )
    return response.data[0].embedding


def text_to_embedding_local(text: str) -> list:
    '''
    Convert text to an embedding using the local sentence-transformers model.
    Returns a 384-dimensional vector (for all-MiniLM-L6-v2). No API call needed.
    '''
    embedding = local_model.encode(text)
    return embedding.tolist()


def text_to_embedding(text: str) -> list:
    '''
    Convert text to an embedding using the configured provider.
    Delegates to either local model or OpenAI based on EMBEDDING_PROVIDER env var.
    '''
    if EMBEDDING_PROVIDER == 'openai':
        return text_to_embedding_oai(text)
    return text_to_embedding_local(text)


def search_oai(query: str, index_path: str = 'snapser-search.ann', num_results: int = 10):
    '''
    Search using OpenAI embeddings (kept for backward compatibility).
    '''
    query_embedding = text_to_embedding_oai(query)
    indices = annoy_index.get_nns_by_vector(query_embedding, num_results)
    return indices


def search_docs(query: str, num_results: int = 10):
    '''
    Search for similar content in the index using the configured embedding provider.
    This is the primary search function used by the /docs-search endpoint.
    '''
    query_embedding = text_to_embedding(query)
    indices = annoy_index.get_nns_by_vector(query_embedding, num_results)
    return indices


def fetch_all_repos(access_token, owner=None, owner_type=None):
    '''
    Fetch all repositories for a given owner and owner type from GitHub.
    '''
    formatted_repos = []
    page = 1
    while True:
        resp = requests.get(
            "https://api.github.com/user/repos",
            headers={"Authorization": f"Bearer {access_token}"},
            params={"per_page": 100, "page": page}
        )
        if resp.status_code != 200:
            break
        repos = resp.json()
        if not repos:
            break

        for repo in repos:
            repo_owner = repo.get("owner", {})
            if owner and repo_owner.get("login") != owner:
                continue
            if owner_type and repo_owner.get("type", "").lower() != owner_type.lower():
                continue

            formatted_repos.append({
                "name": repo["name"],
                "full_name": repo["full_name"],
                "description": repo.get("description", ""),
                "private": repo["private"],
                "owner": {
                    "login": repo_owner.get("login", ""),
                    "type": repo_owner.get("type", "")
                }
            })

        page += 1

    return formatted_repos


@app.route('/v1/cortex/health', methods=['GET'])
def health_check():
    '''
    Health check endpoint to verify if the service is running
    '''
    return jsonify({'status': 'ok'}), 200


@app.route('/v1/cortex/mcp', methods=['POST'])
def mcp():
    '''
    Handle MCP requests
    '''
    data = request.json
    if not data or 'command' not in data or 'input' not in data:
        return jsonify({'error': 'Invalid request, query is required'}), 400
    command = data['command']
    input_text = data['input']
    return jsonify({
        'command': command,
        'input': input_text,
        'output': f'Processed command: {command} with input: {input_text}'
    }), 200


@app.route('/v1/cortex/docs-search', methods=['GET'])
def handle_search():
    '''
    Handle search requests
    '''
    query = request.args.get('q', default='', type=str)
    if not query:
        return jsonify({'error': 'Query parameter is required'}), 400
    try:
        start_time = time.perf_counter()
        result_indices = search_docs(query)
        search_extraction = time.perf_counter()
        results = {'results': [], 'metadata': {
            'nouns': query,
            'time': {
                'search_extraction': search_extraction - start_time
            },
            'indices': result_indices
        }}
        duplicate_lookup = {}
        for index in result_indices:
            file_key = lookup['chunks'][index]
            if file_key in duplicate_lookup:
                continue
            duplicate_lookup[file_key] = True
            docs_path = file_key.replace(
                "./", "/").replace("/index.mdx", "/").replace(".mdx", "")
            result = {
                'category': lookup['lookup'][file_key]['category'],
                'title': lookup['lookup'][file_key]['title'],
                'path': docs_path,
                'url': 'https://snapser.com' + docs_path,
                'snippet': lookup['lookup'][file_key]['description']
            }
            results['results'].append(result)
        # Sort results based on the category (docs first, then API)
        results['results'].sort(
            key=lambda x: 0 if x['category'] == 'doc' else 1)
        return jsonify(results), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/v1/cortex/logs-analysis', methods=['POST'])
def analyze_logs():
    '''
    Analyze a GitHub repository to detect project type, summarize project name,
    and extract features.
    '''
    data = request.json
    logs = data.get("logs")

    if not logs:
        return jsonify({"error": "Missing logs"}), 400
    response = ""
    try:
        response = analyze_snapend_logs(logs)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({
        "analysis": response,
    })


@app.route('/v1/cortex/business-analysis', methods=['POST'])
def analyze_business():
    '''
    Analyze business metrics and provide insights.
    '''
    data = request.json
    business_metrics = data.get("business_metrics")

    if not business_metrics:
        return jsonify({"error": "Missing business metrics"}), 400
    response = ""
    try:
        response = analyze_business_metrics(business_metrics)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({
        "analysis": response,
    })


@app.route('/v1/cortex/github-connect', methods=['POST'])
def github_connect():
    '''
    Connect to GitHub using OAuth and retrieve user information and organizations.
    '''
    data = request.json
    code = data.get("code")

    if not code:
        return jsonify({"error": "Missing GitHub code"}), 400

    try:
        # Step 1: Exchange code for access token
        token_resp = requests.post(
            "https://github.com/login/oauth/access_token",
            headers={"Accept": "application/json"},
            data={
                "client_id": os.getenv('GITHUB_CLIENT_ID'),
                "client_secret": os.getenv('GITHUB_CLIENT_SECRET'),
                "code": code
            }
        )
        token_data = token_resp.json()
        access_token = token_data.get("access_token")
        if not access_token:
            return jsonify({"error": "GitHub token exchange failed", "details": token_data}), 400

        # Step 2: Get user login
        user_resp = requests.get(
            "https://api.github.com/user",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        user_data = user_resp.json()
        login = user_data.get("login")
        if not login:
            return jsonify({"error": "Failed to fetch user login"}), 400

        # Step 3: Get user's orgs
        orgs_resp = requests.get(
            "https://api.github.com/user/orgs",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        orgs_data = orgs_resp.json()
        owners = [{
            "login": user_data.get("login"),
            "type": user_data.get("type"),
            "avatar_url": user_data.get("avatar_url")
        }] + [{
            "login": org.get("login"),
            "type": org.get("type"),
            "avatar_url": org.get("avatar_url")
        } for org in orgs_data if "login" in org]

        return jsonify({
            "access_token": access_token,
            "owners": owners
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/v1/cortex/github-repos', methods=['GET'])
def list_repos_by_owner():
    '''
    List all repositories for a given owner and owner type.
    '''
    access_token = request.args.get("access_token")
    owner = request.args.get("owner")
    owner_type = request.args.get("owner_type", "user")

    if not access_token or not owner:
        return jsonify({"error": "Missing access_token or owner"}), 400

    repos_data = fetch_all_repos(access_token, owner, owner_type)
    return jsonify({
        "repos": repos_data
    })


@app.route('/v1/cortex/github-repo-analysis', methods=['POST'])
def github_analyze_repo():
    '''
    Analyze a GitHub repository to detect project type, summarize project name,
    and extract features.
    '''
    data = request.json
    repo_url = data.get("repo_url")
    access_token = data.get("access_token")
    user_email = data.get("user_email")
    branch = data.get("branch", "main")

    if not repo_url or not access_token or not user_email:
        return jsonify({"error": "Missing repo_url, access_token or user_email. Received " + json.dumps(data)}), 400

    try:
        repo_path = clone(repo_url, branch, access_token, user_email)
        project_type = detect_project_type(repo_path)
        project_summary = summarize_project_name(os.path.basename(repo_path))
        primary_language = detect_primary_language(repo_path)
        scan_response = scan_and_extract(repo_path)

        new_snapser_manager = None
        if primary_language == 'typescript':
            detected_features = scan_response['features'].keys()
            if scan_response['snapser_manager_path']:
                new_snapser_manager = update_snapser_manager_ts(
                    services=detected_features,
                    user_snapser_manager_path=scan_response['snapser_manager_path']
                )
            else:
                new_snapser_manager = generate_new_snapser_manager_ts(
                    services=detected_features
                )
        delete_clone(user_email)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    return jsonify({
        "project_type": project_type,
        "project_summary": project_summary,
        "project_language": primary_language,
        "inferred_features": scan_response['features'],
        "snapser_manager_path": scan_response['snapser_manager_path'],
        "new_snapser_manager": new_snapser_manager,
    })


if __name__ == "__main__":
    # Change debug to True if you are in development
    app.run(host='0.0.0.0', port=5003, debug=False)
