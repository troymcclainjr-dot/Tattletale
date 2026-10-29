"""Builds Officer Steve of Precinct 9 (cop_steve): tall, lanky, glasses, the straight man (cop kit in char_cop_dan.py)."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claykit as ck
from char_cop_dan import build

if __name__ == "__main__":
    build("cop_steve")
