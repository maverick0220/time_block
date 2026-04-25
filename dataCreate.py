
import json
import random as r

startDate = 20250108
config = json.load(open("./lib/config.json", "r", encoding="utf-8"))
events = [event[0] for event in config["eventInfo"]]

outputs = {}

tail = []

def generate_random_segments():
    n = r.randint(10, 30)  # 生成 10-30 个随机的分割点
    # 生成 n-1 个随机的分割点
    points = sorted(r.sample(range(1, 96), n - 1))
    points = [0] + points + [95]
    # print(points)

    # 将分割点转换为段
    segments = [[points[i], points[i + 1]-1, events[r.randint(0,len(events)-1)], "", ""] for i in range(n)]
    segments += [[points[n], 95, "摸鱼", "", ""]]
    # print(segments)
    tail.append(segments[-1][1])
    return segments

for i in range(0, 7):
    day = {f"{startDate + i}": generate_random_segments()}
    outputs.update(day)
# print(outputs)
# print("tail:", tail)

with open('2025.json', 'w', encoding='utf-8') as json_file:
    json.dump(outputs, json_file, ensure_ascii=False, indent=4)
