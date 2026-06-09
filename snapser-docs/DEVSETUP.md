## Developer setup

Docs: https://typer.tiangolo.com/tutorial/package/

Create a python virtualenv and then activate the virtualenv
```bash
# Mac
python3 -m venv .venv
source .venv/bin/activate
```
```bash
# Windows
# Go to the root of the folder and start the virtualenv
.\venv\Scripts\activate
```

Add dependencies
```bash
pip install openai markdown beautifulsoup4 annoy transformers torch
```