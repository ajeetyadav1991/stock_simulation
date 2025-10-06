#!/bin/bash
# FIXED VERSION - Handles PyMuPDF installation issues

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   NARRATIVE QUANTIFIER - FIXED DEPLOYMENT                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Python $(python3 --version)${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Node.js $(node --version)${NC}"

# Check for Xcode Command Line Tools (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! xcode-select -p &> /dev/null; then
        echo -e "${YELLOW}⚠️  Xcode Command Line Tools not found${NC}"
        echo "Installing Xcode Command Line Tools..."
        xcode-select --install
        echo "Please complete the installation and re-run this script"
        exit 1
    fi
    echo -e "${GREEN}✅ Xcode Command Line Tools installed${NC}"
fi

echo ""
echo -e "${BLUE}📁 Creating project structure...${NC}"

mkdir -p backend frontend/src frontend/public data/{uploads,processed} scripts

echo -e "${GREEN}✅ Directories created${NC}"
echo ""

# BACKEND SETUP
echo -e "${BLUE}🐍 Setting up Python backend...${NC}"

cd backend

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}✅ Virtual environment created${NC}"
fi

source venv/bin/activate

# FIXED: Create requirements with flexible PyMuPDF version
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
PyMuPDF>=1.23.0
anthropic>=0.7.0
groq>=0.4.0
requests>=2.31.0
python-multipart==0.0.6
EOF

echo "📦 Installing Python dependencies (this may take 2-3 minutes)..."
pip install --upgrade pip --quiet

# Install packages one by one with error handling
echo "Installing FastAPI..."
pip install fastapi==0.104.1 --quiet || { echo -e "${RED}Failed to install FastAPI${NC}"; exit 1; }

echo "Installing Uvicorn..."
pip install uvicorn[standard]==0.24.0 --quiet || { echo -e "${RED}Failed to install Uvicorn${NC}"; exit 1; }

echo "Installing PyMuPDF (this may take a minute)..."
pip install PyMuPDF --quiet || {
    echo -e "${YELLOW}⚠️  Standard installation failed, trying alternative...${NC}"
    pip install pymupdf-binary --quiet || {
        echo -e "${RED}❌ PyMuPDF installation failed${NC}"
        echo "Try manually: pip install PyMuPDF"
        exit 1
    }
}

echo "Installing AI libraries..."
pip install anthropic --quiet || echo -e "${YELLOW}⚠️  Anthropic optional${NC}"
pip install groq --quiet || echo -e "${YELLOW}⚠️  Groq optional${NC}"
pip install requests python-multipart --quiet

echo -e "${GREEN}✅ Backend dependencies installed${NC}"

# Verify PyMuPDF
python3 << 'PYCHECK'
try:
    import fitz
    print("✅ PyMuPDF (fitz) imported successfully")
except ImportError as e:
    print(f"❌ PyMuPDF import failed: {e}")
    exit(1)
PYCHECK

# Create main.py (same as before - keeping it concise)
cat > main.py << 'BACKEND_EOF'
"""
NARRATIVE QUANTIFIER - Production Backend
"""
import os, re, json, uuid, sqlite3, asyncio
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict

import fitz
from fastapi import FastAPI, UploadFile, File, HTTPException, BackgroundTasks, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

try:
    import anthropic
    ANTHROPIC_AVAILABLE = True
except:
    ANTHROPIC_AVAILABLE = False

try:
    from groq import Groq
    GROQ_AVAILABLE = True
except:
    GROQ_AVAILABLE = False

try:
    import requests
    OLLAMA_AVAILABLE = True
except:
    OLLAMA_AVAILABLE = False

class Settings:
    LLM_PROVIDER = os.getenv("LLM_PROVIDER", "groq").lower()
    ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
    GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
    OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
    OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b")
    MODELS = {"claude": "claude-sonnet-4-20250514", "groq": "llama-3.1-70b-versatile", "ollama": OLLAMA_MODEL}
    MAX_TOKENS = 4000
    TEMPERATURE = 0.1
    UPLOAD_DIR = Path("data/uploads")
    PROCESSED_DIR = Path("data/processed")
    DB_PATH = "data/narrative_quantifier.db"
    MAX_FILE_SIZE = 50 * 1024 * 1024

settings = Settings()
settings.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
settings.PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
Path("data").mkdir(exist_ok=True)

def init_db():
    conn = sqlite3.connect(settings.DB_PATH)
    c = conn.cursor()
    c.execute("CREATE TABLE IF NOT EXISTS companies (symbol TEXT PRIMARY KEY, name TEXT, sector TEXT, created_at TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY, company_symbol TEXT, doc_type TEXT, fiscal_year INTEGER, upload_date TEXT, file_path TEXT, page_count INTEGER, word_count INTEGER)")
    c.execute("CREATE TABLE IF NOT EXISTS risk_metrics (id INTEGER PRIMARY KEY AUTOINCREMENT, company_symbol TEXT, fiscal_year INTEGER, risk_categories TEXT, new_risks TEXT, removed_risks TEXT, sentiment_delta REAL, urgency_score REAL, key_phrases TEXT, analysis_summary TEXT, created_at TEXT)")
    conn.commit()
    conn.close()

init_db()

class LLMClient:
    def __init__(self):
        self.provider = settings.LLM_PROVIDER
        if self.provider == "claude":
            if not ANTHROPIC_AVAILABLE or not settings.ANTHROPIC_API_KEY:
                raise ValueError("Anthropic not available")
            self.client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
        elif self.provider == "groq":
            if not GROQ_AVAILABLE or not settings.GROQ_API_KEY:
                raise ValueError("Groq not available")
            self.client = Groq(api_key=settings.GROQ_API_KEY)
    
    async def generate(self, prompt: str, max_retries: int = 3) -> str:
        for attempt in range(max_retries):
            try:
                if self.provider == "claude":
                    msg = self.client.messages.create(model=settings.MODELS["claude"], max_tokens=settings.MAX_TOKENS, temperature=settings.TEMPERATURE, messages=[{"role": "user", "content": prompt}])
                    return msg.content[0].text
                elif self.provider == "groq":
                    response = self.client.chat.completions.create(model=settings.MODELS["groq"], messages=[{"role": "user", "content": prompt}], max_tokens=settings.MAX_TOKENS, temperature=settings.TEMPERATURE)
                    return response.choices[0].message.content
                elif self.provider == "ollama":
                    response = requests.post(f"{settings.OLLAMA_HOST}/api/generate", json={"model": settings.MODELS["ollama"], "prompt": prompt, "stream": False, "options": {"temperature": settings.TEMPERATURE, "num_predict": settings.MAX_TOKENS}}, timeout=120)
                    return response.json()["response"]
            except Exception as e:
                if attempt < max_retries - 1:
                    await asyncio.sleep(2 ** attempt)
                else:
                    raise HTTPException(status_code=500, detail=str(e))

try:
    llm_client = LLMClient()
except Exception as e:
    print(f"⚠️  LLM Client: {e}")
    llm_client = None

class PDFParser:
    def extract_text(self, pdf_path: str):
        doc = fitz.open(pdf_path)
        text = "\n".join([page.get_text("text") for page in doc])
        text = re.sub(r'\n{3,}', '\n\n', text)
        meta = {'page_count': len(doc), 'word_count': len(text.split())}
        doc.close()
        return text, meta
    
    def extract_section(self, text: str, section: str):
        patterns = {'risk_factors': [r'RISK FACTORS', r'Risk Management']}
        for pattern in patterns.get(section.lower().replace(' ', '_'), []):
            matches = list(re.finditer(pattern, text, re.IGNORECASE))
            if matches:
                return text[matches[0].end():min(matches[0].end() + 15000, len(text))].strip()
        return text[:8000] if text else None

pdf_parser = PDFParser()

def build_prompt(current: str, previous: Optional[str] = None) -> str:
    p = f"Analyze Risk Factors.\n\nCURRENT:\n{current[:6000]}\n"
    if previous:
        p += f"PREVIOUS:\n{previous[:3000]}\n"
    p += 'OUTPUT JSON: {"risk_categories": {}, "new_risks": [], "removed_risks": [], "sentiment_delta": 0, "urgency_score": 0, "key_phrases": [], "summary": ""}'
    return p

app = FastAPI(title="Narrative Quantifier API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

analysis_jobs = {}

class CompanyCreate(BaseModel):
    symbol: str
    name: str
    sector: Optional[str] = None

@app.get("/")
async def root():
    return {"message": "Narrative Quantifier", "version": "1.0.0"}

@app.get("/api/health")
async def health():
    return {"status": "healthy", "llm_provider": settings.LLM_PROVIDER, "llm_available": llm_client is not None}

@app.post("/api/companies")
async def create_company(company: CompanyCreate):
    conn = sqlite3.connect(settings.DB_PATH)
    try:
        conn.execute("INSERT INTO companies VALUES (?, ?, ?, ?)", (company.symbol.upper(), company.name, company.sector, datetime.now().isoformat()))
        conn.commit()
        return {"message": "Created", "symbol": company.symbol.upper()}
    except sqlite3.IntegrityError:
        raise HTTPException(400, "Company exists")
    finally:
        conn.close()

@app.get("/api/companies")
async def list_companies():
    conn = sqlite3.connect(settings.DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM companies ORDER BY symbol").fetchall()
    conn.close()
    return [dict(row) for row in rows]

@app.post("/api/documents/upload")
async def upload(file: UploadFile = File(...), company_symbol: str = Form(...), fiscal_year: int = Form(...)):
    content = await file.read()
    if len(content) > settings.MAX_FILE_SIZE:
        raise HTTPException(400, "File too large")
    doc_id = str(uuid.uuid4())
    file_path = settings.UPLOAD_DIR / f"{doc_id}.pdf"
    with open(file_path, "wb") as f:
        f.write(content)
    try:
        text, meta = pdf_parser.extract_text(str(file_path))
        text_path = settings.PROCESSED_DIR / f"{doc_id}.txt"
        with open(text_path, "w", encoding="utf-8") as f:
            f.write(text)
        conn = sqlite3.connect(settings.DB_PATH)
        conn.execute("INSERT INTO documents VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (doc_id, company_symbol.upper(), "annual_report", fiscal_year, datetime.now().isoformat(), str(file_path), meta['page_count'], meta['word_count']))
        conn.commit()
        conn.close()
        return {"doc_id": doc_id, "company_symbol": company_symbol.upper(), "fiscal_year": fiscal_year, "page_count": meta['page_count'], "word_count": meta['word_count'], "message": "Uploaded"}
    except Exception as e:
        file_path.unlink(missing_ok=True)
        raise HTTPException(500, str(e))

async def analyze_job(job_id: str, company: str, year: int):
    try:
        analysis_jobs[job_id] = {"status": "processing", "progress": 20, "message": "Loading"}
        conn = sqlite3.connect(settings.DB_PATH)
        conn.row_factory = sqlite3.Row
        current = conn.execute("SELECT * FROM documents WHERE company_symbol = ? AND fiscal_year = ?", (company, year)).fetchone()
        previous = conn.execute("SELECT * FROM documents WHERE company_symbol = ? AND fiscal_year = ?", (company, year - 1)).fetchone()
        conn.close()
        if not current:
            analysis_jobs[job_id] = {"status": "failed", "progress": 0, "message": "Doc not found"}
            return
        analysis_jobs[job_id]["progress"] = 40
        with open(settings.PROCESSED_DIR / f"{current['id']}.txt", "r") as f:
            curr_text = f.read()
        curr_risk = pdf_parser.extract_section(curr_text, 'risk_factors')
        prev_risk = None
        if previous:
            with open(settings.PROCESSED_DIR / f"{previous['id']}.txt", "r") as f:
                prev_risk = pdf_parser.extract_section(f.read(), 'risk_factors')
        analysis_jobs[job_id]["progress"] = 60
        prompt = build_prompt(curr_risk, prev_risk)
        response = await llm_client.generate(prompt)
        response = response.replace('```json\n', '').replace('\n```', '').strip()
        result = json.loads(response)
        analysis_jobs[job_id]["progress"] = 80
        conn = sqlite3.connect(settings.DB_PATH)
        conn.execute("INSERT INTO risk_metrics (company_symbol, fiscal_year, risk_categories, new_risks, removed_risks, sentiment_delta, urgency_score, key_phrases, analysis_summary, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", 
            (company, year, json.dumps(result['risk_categories']), json.dumps(result.get('new_risks', [])), json.dumps(result.get('removed_risks', [])), result.get('sentiment_delta', 0.0), result['urgency_score'], json.dumps(result['key_phrases']), result['summary'], datetime.now().isoformat()))
        conn.commit()
        conn.close()
        analysis_jobs[job_id] = {"status": "completed", "progress": 100, "message": "Complete", "result": result}
    except Exception as e:
        analysis_jobs[job_id] = {"status": "failed", "progress": 0, "message": str(e)}

@app.post("/api/analysis/risk-evolution")
async def start_analysis(company_symbol: str = Form(...), fiscal_year: int = Form(...), background_tasks: BackgroundTasks = None):
    if not llm_client:
        raise HTTPException(500, "LLM not configured")
    job_id = str(uuid.uuid4())
    analysis_jobs[job_id] = {"status": "pending", "progress": 0, "message": "Queued"}
    background_tasks.add_task(analyze_job, job_id, company_symbol.upper(), fiscal_year)
    return {"job_id": job_id, "message": "Started"}

@app.get("/api/analysis/status/{job_id}")
async def status(job_id: str):
    if job_id not in analysis_jobs:
        raise HTTPException(404, "Job not found")
    return analysis_jobs[job_id]

@app.get("/api/results/risk-evolution/{company_symbol}")
async def results(company_symbol: str):
    conn = sqlite3.connect(settings.DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM risk_metrics WHERE company_symbol = ? ORDER BY fiscal_year", (company_symbol.upper(),)).fetchall()
    conn.close()
    return [{"fiscal_year": r['fiscal_year'], "risk_categories": json.loads(r['risk_categories']), "new_risks": json.loads(r['new_risks']), "removed_risks": json.loads(r['removed_risks']), "sentiment_delta": r['sentiment_delta'], "urgency_score": r['urgency_score'], "key_phrases": json.loads(r['key_phrases']), "summary": r['analysis_summary'], "analyzed_at": r['created_at']} for r in rows]

@app.get("/api/documents/{company_symbol}")
async def docs(company_symbol: str):
    conn = sqlite3.connect(settings.DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM documents WHERE company_symbol = ? ORDER BY fiscal_year DESC", (company_symbol.upper(),)).fetchall()
    conn.close()
    return [dict(r) for r in rows]

@app.on_event("startup")
async def startup():
    print("\n" + "="*60)
    print("🚀 NARRATIVE QUANTIFIER API")
    print(f"📊 LLM: {settings.LLM_PROVIDER.upper()}")
    print("="*60 + "\n")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
BACKEND_EOF

echo -e "${GREEN}✅ Backend created${NC}"

cd ..

# Continue with frontend setup (same as original)...
echo ""
echo -e "${BLUE}⚛️  Setting up frontend...${NC}"

cd frontend

cat > package.json << 'EOF'
{
  "name": "narrative-quantifier-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "recharts": "^2.10.3",
    "lucide-react": "^0.294.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "devDependencies": {
    "tailwindcss": "^3.3.5",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32"
  },
  "proxy": "http://localhost:8000",
  "browserslist": {
    "production": [">0.2%", "not dead"],
    "development": ["last 1 chrome version"]
  }
}
EOF

echo "📦 Installing frontend dependencies..."
npm install --silent 2>/dev/null || npm install

npx tailwindcss init -p >/dev/null 2>&1

cat > tailwind.config.js << 'EOF'
module.exports = {
  content: ["./src/**/*.{js,jsx}", "./public/index.html"],
  theme: { extend: {} },
  plugins: [],
}
EOF

cat > src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

cat > src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';
const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<React.StrictMode><App /></React.StrictMode>);
EOF

cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Narrative Quantifier</title>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
EOF

echo -e "${GREEN}✅ Frontend setup complete${NC}"
echo ""
echo -e "${YELLOW}⚠️  You must manually add frontend/src/App.jsx${NC}"

cd ..

# Environment and scripts
cat > .env << 'EOF'
LLM_PROVIDER=groq
GROQ_API_KEY=your_groq_api_key_here
ANTHROPIC_API_KEY=
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=llama3.1:8b
EOF

mkdir -p scripts
cat > scripts/run_backend.sh << 'EOF'
#!/bin/bash
cd backend
source venv/bin/activate
export $(cat ../.env | xargs)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
EOF
chmod +x scripts/run_backend.sh

cat > scripts/run_frontend.sh << 'EOF'
#!/bin/bash
cd frontend
npm start
EOF
chmod +x scripts/run_frontend.sh

cat > scripts/run_all.sh << 'EOF'
#!/bin/bash
./scripts/run_backend.sh &
BACKEND_PID=$!
sleep 3
./scripts/run_frontend.sh &
FRONTEND_PID=$!
trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; exit" INT TERM
wait
EOF
chmod +x scripts/run_all.sh

cat > README.md << 'EOF'
# Narrative Quantifier

## Quick Start
1. Add App.jsx: Copy 'complete_frontend_app' artifact to frontend/src/App.jsx
2. Get API key: https://console.groq.com
3. Configure: nano .env (add GROQ_API_KEY)
4. Run: ./scripts/run_all.sh
5. Open: http://localhost:3000
EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ SETUP COMPLETE!${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "NEXT STEPS:"
echo "1. Copy frontend code: frontend/src/App.jsx"
echo "2. Get API key: https://console.groq.com"
echo "3. Configure: nano .env"
echo "4. Run: ./scripts/run_all.sh"
echo ""