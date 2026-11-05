#!/usr/bin/env python3
"""Fast, dependency-free smoke test: python verify_42.py."""
from forty_two import DIGIT_4, DIGIT_2, FORTY_TWO_POINTS, render_42

def run():
    assert len(DIGIT_4) == len(DIGIT_2) == 9
    assert len(FORTY_TWO_POINTS) > 1000
    for w, h in [(30,12),(72,28),(120,48)]:
        for a,b in [(0,0),(0.8,1.3),(3.2,2.1)]:
            lines = render_42(w,h,a,b)
            assert len(lines) == h
            assert all(len(x) == w for x in lines)
            assert any(any(ch != ' ' for ch in x) for x in lines)
    print(f'PASS: source voxel cloud {len(FORTY_TWO_POINTS)} points, 9 frames, 3 dimensions')

if __name__ == '__main__': run()
