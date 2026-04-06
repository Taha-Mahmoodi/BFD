from __future__ import annotations


APP_QSS = """
QMainWindow, QWidget#Root {
    background: #f5f4f0;
    color: #111111;
    font-family: "Geologica", "Bahnschrift", "Segoe UI", sans-serif;
    font-size: 14px;
}
QLabel#BrandLabel {
    font-size: 30px;
    font-weight: 800;
}
QLabel#HeaderCenterText {
    font-size: 30px;
    font-weight: 800;
}
QLabel#HeaderTitle {
    font-size: 30px;
    font-weight: 800;
    color: #344c4c;
}
QLabel#SectionTitle {
    font-size: 26px;
    font-weight: 400;
    color: #f95c4b;
}
QLabel#BodyText {
    font-size: 20px;
    color: #344c4c;
}
QLabel#MutedText {
    font-size: 8px;
    color: #9b9b9b;
}
QFrame#HeaderPillBlack {
    background: #000000;
    border-radius: 16px;
}
QFrame#HeaderPillCoral {
    background: #f95c4b;
    border-radius: 16px;
}
QFrame#HeaderPillSand {
    background: #e4ded2;
    border-radius: 16px;
}
QFrame#StepActive {
    background: #344c4c;
    border-radius: 42px;
}
QFrame#StepInactive {
    background: #dcdcdc;
    border-radius: 42px;
}
QLabel#StepText {
    font-size: 50px;
    color: #f5f4f0;
    font-weight: 400;
}
QPushButton {
    border-radius: 16px;
    padding: 0 24px;
    font-size: 30px;
    font-weight: 800;
}
QPushButton#PrimaryButton {
    background: #344c4c;
    color: #ffffff;
    border: none;
}
QPushButton#DangerButton {
    background: #ff1900;
    color: #ffffff;
    border: none;
}
QPushButton#SecondaryButton {
    background: #f5f4f0;
    color: #111111;
    border: 2px solid #f95c4b;
}
QPushButton#TinyButton {
    background: #f5f4f0;
    color: #9b9b9b;
    border: 1px solid #f95c4b;
    border-radius: 8px;
    font-size: 8px;
    font-weight: 400;
    padding: 0 4px;
}
QPushButton:disabled {
    background: #c9c9c9;
    color: #efefef;
    border-color: #c9c9c9;
}
QCheckBox#ProviderCheck {
    font-size: 36px;
    font-weight: 800;
    spacing: 10px;
    color: #9b9b9b;
}
QCheckBox#ProviderCheck:checked {
    color: #f95c4b;
}
QCheckBox#ProviderCheck::indicator {
    width: 30px;
    height: 30px;
    border: 3px solid #9b9b9b;
    border-radius: 15px;
    background: #f5f4f0;
}
QCheckBox#ProviderCheck::indicator:checked {
    background: #344c4c;
}
QCheckBox#ControlCheck {
    font-size: 20px;
    font-weight: 400;
    spacing: 10px;
    color: #111111;
}
QCheckBox#ControlCheck::indicator {
    width: 34px;
    height: 34px;
    border: 2px solid #1a1a1a;
    border-radius: 0px;
    background: #f5f4f0;
}
QCheckBox#ControlCheck::indicator:checked {
    background: #344c4c;
}
QLineEdit {
    border: 1px solid #f95c4b;
    border-radius: 8px;
    padding: 8px 12px;
    font-size: 20px;
    color: #344c4c;
    background: #f5f4f0;
}
QProgressBar {
    border: 1px solid #f95c4b;
    border-radius: 999px;
    background: #f5f4f0;
    min-height: 19px;
    max-height: 19px;
    color: #344c4c;
    text-align: center;
}
QProgressBar::chunk {
    background: #f95c4b;
    border-radius: 999px;
}
QPlainTextEdit {
    border: 5px solid #f95c4b;
    border-radius: 20px;
    background: #e4ded2;
    font-size: 14px;
    padding: 8px;
}
QGroupBox {
    border: none;
    margin-top: 8px;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 0px;
    padding: 0 2px;
    font-size: 20px;
    color: #344c4c;
}
"""
