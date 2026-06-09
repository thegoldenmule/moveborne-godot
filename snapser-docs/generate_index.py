'''
  This script generates an index for a set of markdown and swagger files in a directory
  and allows you to search for similar content using either a local sentence-transformers model
  or OpenAI's text-embedding-ada-002 model, with Annoy's approximate nearest neighbors search.

  @Author: Ajinkya Apte
  @Company: Snapser Inc.

  Usage:
    Default (local model, no API key needed):
      python generate_index.py

    To use OpenAI instead:
      EMBEDDING_PROVIDER=openai OPENAI_API_KEY=sk-... python generate_index.py
'''
import os
import json
# import shutil
# from pathlib import Path
from typing import Union
import markdown
from transformers import GPT2Tokenizer
from bs4 import BeautifulSoup
from openai import OpenAI
from openai.types import CreateEmbeddingResponse
from annoy import AnnoyIndex
from sentence_transformers import SentenceTransformer
# import torch
# from transformers import BertTokenizer, BertModel

# ── Embedding provider config ──────────────────────────────────────────
# Set EMBEDDING_PROVIDER=openai to use OpenAI, otherwise defaults to local
EMBEDDING_PROVIDER = os.getenv('EMBEDDING_PROVIDER', 'local')  # 'local' or 'openai'
LOCAL_MODEL_NAME = 'all-MiniLM-L6-v2'  # 384 dimensions, ~80MB, runs on CPU

# Load local model once at module level (only if using local provider)
local_model = None
if EMBEDDING_PROVIDER == 'local':
    print(f"Loading local embedding model: {LOCAL_MODEL_NAME}...")
    local_model = SentenceTransformer(LOCAL_MODEL_NAME)
    print("Local model loaded successfully.")


# Helper class


class MissingEnvironmentVariableError(Exception):
    """Exception raised when a required environment variable is missing."""
    pass

# Helper functions


def markdown_to_text(markdown_string: str) -> str:
    '''
    Convert markdown to plain text
    '''
    html = markdown.markdown(markdown_string)
    return ''.join(BeautifulSoup(html, "html.parser").findAll(string=True))


def extract_text_from_swagger(swagger: dict) -> list:
    '''
    Extract simplified text snippets from a Swagger JSON file.
    Focuses only on the operation ID, endpoint name, and description.
    '''
    text_snippets = []

    # Assuming Swagger 2.0 or OpenAPI 3.0 format
    for path, methods in swagger.get('paths', {}).items():
        for method, details in methods.items():
            # Get operation ID, summary, and description
            operation_id = details.get('operationId', 'Unnamed Operation')
            summary = details.get('summary', '')
            description = details.get('description', '')
            # Build a basic text representation of each endpoint
            full_text = f"{operation_id}: {summary} {description}"
            text_snippets.append(full_text.strip())
    return text_snippets


# TODO: See if we can use BERT embeddings instead of OpenAI's text-embedding-ada-002
#   My testing told me that BERT embeddings are not as good as OpenAI's text-embedding-ada-002
# tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
# model = BertModel.from_pretrained('bert-base-uncased')
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


def text_to_embedding_oai(text):
    '''
    Convert text to an embedding using OpenAI's text-embedding-ada-002 model
    Returns a 1536-dimensional vector
    '''
    client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
    response: CreateEmbeddingResponse = client.embeddings.create(
        input=text,
        model="text-embedding-ada-002"
    )
    return response.data[0].embedding


def text_to_embedding_local(text):
    '''
    Convert text to an embedding using a local sentence-transformers model
    Returns a 384-dimensional vector (for all-MiniLM-L6-v2)
    '''
    embedding = local_model.encode(text)
    return embedding.tolist()


def text_to_embedding(text):
    '''
    Convert text to an embedding using the configured provider.
    Delegates to either local or OpenAI based on EMBEDDING_PROVIDER env var.
    '''
    if EMBEDDING_PROVIDER == 'openai':
        return text_to_embedding_oai(text)
    return text_to_embedding_local(text)


def search(query, index_path='snapser-search.ann', num_results=10):
    '''
    Search for similar content in the index using the query
    '''
    query_embedding = text_to_embedding(query)
    u = AnnoyIndex(len(query_embedding), 'angular')
    u.load(index_path)  # mmap the file

    # Find the nearest neighbors
    indices = u.get_nns_by_vector(query_embedding, num_results)
    return indices


def smart_chunk(text, max_length=1024):
    '''
    Split the text into chunks of a maximum length
    '''
    tokenizer = GPT2Tokenizer.from_pretrained('gpt2')
    tokens = tokenizer.tokenize(text)
    chunks = []

    current_chunk = []
    current_length = 0
    for token in tokens:
        current_chunk.append(token)
        current_length += 1
        if current_length >= max_length:
            chunks.append(tokenizer.convert_tokens_to_string(current_chunk))
            current_chunk = []
            current_length = 0
    if current_chunk:
        chunks.append(tokenizer.convert_tokens_to_string(current_chunk))

    return chunks


def write_to_json_file(data: object, file_path: str) -> None:
    '''
    Write the data to a json file at the specified path
    '''
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)


# Step 1

def build_docs_list(directory: str, deny_list: Union[list, None] = None) -> dict:
    '''
    Build a list of dictionaries containing the name, path, title, and description of
    each markdown file in the directory
    '''
    tree_list = {}
    for root, dirs, files in os.walk(directory):
        for file in files:
            if deny_list is not None and file in deny_list:
                continue
            if file.endswith(".mdx"):
                full_path = os.path.join(root, file)
                relative_path = os.path.relpath(full_path, start=directory)
                with open(full_path, 'r', encoding='utf-8') as f:
                    content = f.readlines()
                    # Filter out lines starting with 'export'
                    content = [
                        line for line in content if not line.startswith('export')]

                    # Find the first line starting with '#' and use it as the title
                    title_line = None
                    for line in content:
                        if line.strip().startswith('#'):
                            title_line = line
                            break

                    description = 'View Document'
                    if title_line:
                        # Get the index of the title line
                        title_index = content.index(title_line)
                        # Start collecting description lines after the title line until another
                        # header is found
                        description_lines = []
                        total_characters = 0
                        previous_last_character = ''
                        for line in content[title_index + 1:]:
                            if line.strip().startswith(('#', '##', '###', '####')) or \
                               line == '\n':
                                continue
                            desc_line = line.strip()
                            if previous_last_character not in [' ']:
                                desc_line = desc_line + ' '
                            desc_line = desc_line.replace('**', '')
                            description_lines.append(desc_line)
                            total_characters += len(desc_line)
                            if total_characters >= 200:
                                break
                            if len(line) > 1:
                                previous_last_character = line.strip()[-1]
                            else:
                                previous_last_character = ''
                        description = ''.join(description_lines)[
                            :200] + '...' if description_lines else 'View Document'
                tree_list[f"{directory}/{relative_path}"] = {
                    'name': file,
                    'title': title_line.replace('#', '').strip().title(),
                    'description': description,
                    'category': 'doc'
                    # 'order': 0
                }
    return tree_list


def build_swagger_list(directory: str, deny_list: Union[list, None] = None) -> dict:
    '''
    Build a list of dictionaries containing the name, path, title, and description of
    each markdown file in the directory
    '''
    tree_list = {}
    for root, dirs, files in os.walk(directory):
        for file in files:
            if deny_list is not None and file in deny_list:
                continue
            if file.endswith(".json"):
                description = 'API Documentation'
                # with open(f"{directory}/{file}", 'r', encoding='utf-8') as file_contents:
                #     swagger = json.load(file_contents)
                #     description = ', '.join(extract_text_from_swagger(swagger))
                full_path = os.path.join(root, file)
                relative_path = os.path.relpath(full_path, start=directory)
                tree_list[f"{directory}/{relative_path}"] = {
                    'name': file,
                    'title': file.split('.')[0].title(),
                    'description': description,
                    'category': 'api'
                    # 'order': 0
                }
    return tree_list


# Step 2

def build_search_index(embeddings: list, file_name: str):
    '''
    Build an Annoy index for storing embeddings
    '''
    f = len(embeddings[0])  # Length of item vector that will be indexed
    t = AnnoyIndex(f, 'angular')

    for i, vec in enumerate(embeddings):
        t.add_item(i, vec)

    t.build(10)  # 40 trees changed from 10
    t.save(file_name)


def load_and_index_files(
        tree_dict: Union[dict, None] = None, index_filename: str = 'snapser.ann') -> list:
    '''
    Load the files from the tree list and index
    '''
    if tree_dict is None:
        tree_dict = {}
    embeddings_list = []
    embeddings = []
    for key, value in tree_dict.items():
        with open(key, 'r', encoding='utf-8') as file:
            plain_text: str = ''
            if value['category'] == 'doc':
                markdown_content = file.read()
                chunks = smart_chunk(markdown_to_text(
                    markdown_content), max_length=1024)
                for index, chunk in enumerate(chunks):
                    embedding = text_to_embedding(
                        chunk)  # Embed full chunk
                    embeddings.append(embedding)
                    embeddings_list.append(key)
            elif value['category'] == 'api':
                swagger = json.load(file)
                plain_text = ', '.join(extract_text_from_swagger(swagger))
                chunks = smart_chunk(plain_text, max_length=1024)
                for index, chunk in enumerate(chunks):
                    embedding = text_to_embedding(
                        chunk)  # Embed full chunk
                    embeddings.append(embedding)
                    embeddings_list.append(key)
            # embedding = text_to_embedding(plain_text)
            # embeddings.append(embedding)
    build_search_index(embeddings, index_filename)
    return embeddings_list


# Main function to run the script
if __name__ == '__main__':
    print(f"Using embedding provider: {EMBEDDING_PROVIDER}")
    if EMBEDDING_PROVIDER == 'openai' and os.getenv('OPENAI_API_KEY') is None:
        raise MissingEnvironmentVariableError(
            "Please set your OpenAI API key in the environment variable OPENAI_API_KEY")
    DOCS_DIR = './docs'
    SWAGGER_DIR = './swagger'
    DENY_LIST = []
    SUMMARY_FILE = 'snapser-search.json'
    SNAPSER_INDEX_FILENAME = 'snapser-search.ann'
    # Step 1 - Build the index list
    index_dict = build_docs_list(DOCS_DIR, DENY_LIST)
    swagger_dict = build_swagger_list(SWAGGER_DIR, DENY_LIST)
    merged_dict = {**index_dict, **swagger_dict}
    # Step 2 - Load the embeddings and index the files
    embedding_list = load_and_index_files(merged_dict, SNAPSER_INDEX_FILENAME)
    final_dict = {
        'chunks': embedding_list,
        'lookup': merged_dict
    }
    # Step 3 - Write the final dictionary to a JSON file
    write_to_json_file(final_dict, SUMMARY_FILE)
