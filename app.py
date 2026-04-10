from flask import Flask, render_template, request, jsonify
from google import genai
from dotenv import load_dotenv
import os

load_dotenv()

app = Flask(__name__)
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/recommend", methods=["POST"])
def recommend():
    query = request.json.get("query", "").strip()
    if not query:
        return jsonify({"error": "검색어를 입력해주세요."}), 400

    prompt = f"""사용자가 "{query}"를 검색했습니다.
이 장소와 관련된 실제 장소 3곳을 추천해주세요.

반드시 아래 형식으로만 답변하세요. 번호, 이름, 한 줄 설명만 적고 다른 말은 하지 마세요:

1. [장소명] - [한 줄 설명]
2. [장소명] - [한 줄 설명]
3. [장소명] - [한 줄 설명]"""

    response = client.models.generate_content(
        model="gemini-2.5-flash-lite",
        contents=prompt
    )

    return jsonify({"result": response.text})


if __name__ == "__main__":
    app.run(debug=True)
