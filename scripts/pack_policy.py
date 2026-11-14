"""Общий отбор пакетов: первый отыгрыш, десять лет, отдельный набор 18+."""
from datetime import date, datetime
import re
from zoneinfo import ZoneInfo

ADULT = re.compile(r'(?i)(?<!\d)18\s*\+|для\s+взрослых|ненормативн\w*\s+лексик|ч[её]рн\w*\s+(?:чгк|тематик)')
RZHEVSKY = re.compile(r'(?i)куб\w*\s+(?:поручика\s+)?ржевск\w*')
REVIEW = re.compile(r'(?i)эротич|порнограф|нецензур|возрастн\w*\s+огранич|сексуальн\w*\s+тематик')


def today():
    return datetime.now(ZoneInfo('Europe/Minsk')).date()


def cutoff(as_of=None):
    day = as_of or today()
    try:
        return day.replace(year=day.year - 10)
    except ValueError:
        return day.replace(year=day.year - 10, day=28)


def play_date(value):
    """Дата первого отыгрыша; публикация и загрузка её не заменяют."""
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value.removeprefix('$D')[:10]).isoformat()
    except ValueError:
        return None


def in_horizon(value, as_of=None):
    day = as_of or today()
    parsed = play_date(value)
    return parsed is not None and cutoff(day).isoformat() <= parsed <= day.isoformat()


def audience(pack):
    """Категория и основание. adultOnly=False не отменяет предупреждения автора."""
    if pack.get('adultOnly') is True:
        return 'adult', 'adultOnly=true'
    if RZHEVSKY.search(' '.join(pack.get(k) or '' for k in ('title','longTitle'))):
        return 'adult', 'серия «Кубок Ржевского»: подтверждено игроком 14.11.2026'
    for field in ('title', 'longTitle', 'info'):
        text = pack.get(field) or ''
        if ADULT.search(text):
            return 'adult', f'{field}: явная маркировка 18+ или предупреждение автора'
    text = ' '.join(pack.get(k) or '' for k in ('title','longTitle','info'))
    if REVIEW.search(text) or (pack.get('info') or '').startswith('$'):
        return 'review', 'неоднозначное или нераскрытое описание'
    if not pack.get('metadataChecked'):
        return 'review', 'метаданные пакета ещё не проверены'
    return 'standard', 'в проверенных метаданных нет признаков взрослого пакета'
