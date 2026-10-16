#!/usr/bin/env python3
"""Populate the hero recording's static past-day tiles, preserving today's animation."""
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'site/assets'


def run(*args):
    subprocess.run(args, check=True)


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    # Always start from the original recording, never from a previously filled output.
    original = subprocess.check_output(
        ['git', 'show', 'f6779a380725dd0761a34870ff626a3a49aa361c'], cwd=ROOT)
    source = work / 'original.mp4'
    source.write_bytes(original)
    header = '''[Script Info]
ScriptType: v4.00+
PlayResX: 720
PlayResY: 1566
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
'''
    lines = [header]
    # 23 complete weeks and two past days in the current week. Leave today
    # and future cells untouched so the recorded completion still plays normally.
    days = [(column, row) for column in range(24) for row in range(7)
            if column < 23 or row < 2]
    for habit, (top, color) in enumerate([(575, 'F46B22'), (1001, '2E83F7'), (1428, '33AD69')]):
        selected = random.Random(70 + habit).sample(days, round(len(days) * .7))
        paths = []
        for column, row in selected:
            x, y = round(139 + column * 21.6), round(top + row * 21.6)
            # Rounded 16-point tiles match the existing native grid cells.
            paths.append(f'm {x+2} {y} l {x+14} {y} b {x+16} {y} {x+16} {y} {x+16} {y+2} l {x+16} {y+14} b {x+16} {y+16} {x+16} {y+16} {x+14} {y+16} l {x+2} {y+16} b {x} {y+16} {x} {y+16} {x} {y+14} l {x} {y+2} b {x} {y} {x} {y} {x+2} {y}')
        ass_color = color[4:6] + color[2:4] + color[:2]
        lines.append('Dialogue: 0,0:00:00.00,0:01:00.00,Default,,0,0,0,,{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H' + ass_color + '&\\p1}' + ' '.join(paths) + '\n')
        print(f'Habit {habit+1}: {len(selected)}/{len(days)} past days completed')
    overlay = work / 'history.ass'
    overlay.write_text(''.join(lines))
    output = ASSETS / 'completion-interaction.mp4'
    run('ffmpeg', '-y', '-loglevel', 'error', '-i', str(source), '-vf', f'ass={overlay}',
        '-an', '-c:v', 'libx264', '-crf', '18', '-preset', 'slow', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart', str(output))
    run('ffmpeg', '-y', '-loglevel', 'error', '-i', str(output), '-an', '-c:v', 'libvpx-vp9',
        '-crf', '25', '-b:v', '0', '-row-mt', '1', str(ASSETS / 'completion-interaction.webm'))
    run('ffmpeg', '-y', '-loglevel', 'error', '-i', str(output), '-frames:v', '1',
        '-vf', 'scale=1206:2622', str(ASSETS / 'iphone-overview-light.png'))
