import time

from ollama import chat

models = [
    "tinyllama:1.1b",
    "llama3.2:1b",
    "qwen2.5:3b-instruct",
]

while True:
    param = int(input("モデル： (1: tinyllama, 2: llama3.2, 3: qwen2.5): ")) - 1
    question = input("質問：")
    start = time.perf_counter()
    res = chat(
        model=models[param],
        messages=[
            {
                "role": "system",
                "content": "あなたは親切で知識豊富なアシスタントです。日本語で分かりやすく回答してください。",
            },
            {"role": "user", "content": question},
        ],
    )
    end = time.perf_counter()
    elapsed = end - start
    print(f"回答：{res['message']['content']}")
    print(f"時間：{elapsed:.3f}秒")
    print(f"{'-' * 72}\n")
