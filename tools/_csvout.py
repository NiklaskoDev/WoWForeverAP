"""CSV output shared by the import tools: the quests.csv column order and the header-comment writer."""
import csv
import io
from pathlib import Path

QUEST_COLUMNS = ("quest_id", "name", "zone_ui_map_id", "req_level", "faction", "release",
                 "prereq_quest_ids", "extra_zone_ids", "name_suffix")


def render_csv(comments: list[str], columns: tuple[str, ...], rows: list[tuple]) -> str:
    """The file text: one ``# comment`` line each, the header, then the rows (``\\n`` line ends)."""
    buffer = io.StringIO()
    for comment in comments:
        buffer.write(f"# {comment}\n")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(columns)
    writer.writerows(rows)
    return buffer.getvalue()


def write_csv(path: Path, comments: list[str], columns: tuple[str, ...], rows: list[tuple]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(render_csv(comments, columns, rows))
