"""
에러/이상치 발생 시 Outlook 데스크톱 앱을 통해 본인에게만 메일을 발송한다.
Windows + Outlook 데스크톱 앱 설치 환경에서만 동작한다 (win32com 사용).
"""
from __future__ import annotations

from config import OUTLOOK_RECIPIENT


def send_alert(subject: str, body: str) -> None:
    """
    본인에게만 알림 메일을 보낸다. Windows가 아니거나 Outlook이 없으면
    콘솔에 동일 내용을 출력하는 것으로 대체한다 (개발/테스트 환경 대응).
    """
    try:
        import win32com.client  # type: ignore

        outlook = win32com.client.Dispatch("Outlook.Application")
        mail = outlook.CreateItem(0)  # olMailItem
        mail.To = OUTLOOK_RECIPIENT
        mail.Subject = subject
        mail.Body = body
        mail.Send()
    except ImportError:
        print("[Outlook 미사용 환경] 아래 내용을 콘솔에 대신 출력합니다.")
        print(f"To: {OUTLOOK_RECIPIENT}")
        print(f"Subject: {subject}")
        print(body)
