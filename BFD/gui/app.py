
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import sys
import tempfile
import uuid

from PySide6.QtCore import Qt, QProcess
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QFileDialog,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from event_protocol import GuiEvent, parse_gui_event_line
from process_control import resume_process_tree, suspend_process_tree, terminate_process_tree
from settings_store import load_settings, save_settings
from theme import APP_QSS


PROVIDERS = [
    ("google_fonts", "Google Fonts", True, True),
    ("font_hub", "Font Hub", False, True),
    ("dafont", "DaFont", False, True),
    ("font_share", "Font Share", False, True),
    ("font_face", "Font Face", False, False),
    ("open_foundry", "Open Foundry", False, True),
    ("befonts", "Befonts", False, True),
]

PROVIDER_ESTIMATE = {
    "google_fonts": {"size_gb": 20.0, "time_hours": 0.45},
    "font_hub": {"size_gb": 8.0, "time_hours": 0.20},
    "dafont": {"size_gb": 8.0, "time_hours": 0.20},
    "font_share": {"size_gb": 5.0, "time_hours": 0.15},
    "open_foundry": {"size_gb": 4.0, "time_hours": 0.15},
    "befonts": {"size_gb": 5.0, "time_hours": 0.15},
}


class BfdWizardWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("BFD (Bulk Font Downloader) v1.0.0")

        self._settings = load_settings()
        self._current_step = 0
        self._state = "idle"
        self._stdout_buffer = ""
        self._stderr_buffer = ""
        self._control_file: Path | None = None
        self._last_output_folder = ""
        self._phase = "download"
        self._cancel_requested = False
        self._bulk_sync_in_progress = False

        self._process = QProcess(self)
        self._process.readyReadStandardOutput.connect(self._on_stdout)
        self._process.readyReadStandardError.connect(self._on_stderr)
        self._process.finished.connect(self._on_finished)

        self._provider_checks: dict[str, QCheckBox] = {}

        self._build_ui()
        self._restore_settings()
        self._apply_step(0)

    def _build_ui(self) -> None:
        root = QWidget(self)
        root.setObjectName("Root")
        self.setCentralWidget(root)

        layout = QVBoxLayout(root)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(16)

        layout.addWidget(self._build_header())
        layout.addWidget(self._build_steps())

        self.page_stack = QStackedWidget(root)
        self.page_stack.addWidget(self._build_step1())
        self.page_stack.addWidget(self._build_step2())
        self.page_stack.addWidget(self._build_step3())
        self.page_stack.addWidget(self._build_step4())
        layout.addWidget(self.page_stack, stretch=1)

        layout.addWidget(self._build_footer())

        self.setStyleSheet(APP_QSS)

    def _build_header(self) -> QWidget:
        header = QWidget(self)
        row = QHBoxLayout(header)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(18)

        left = QFrame(header)
        left.setObjectName("HeaderPillCoral")
        left.setFixedSize(123, 78)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        lbl_left = QLabel("BFD", left)
        lbl_left.setObjectName("BrandLabel")
        lbl_left.setStyleSheet("color: white;")
        lbl_left.setAlignment(Qt.AlignCenter)
        left_layout.addWidget(lbl_left)

        center = QFrame(header)
        center.setObjectName("HeaderPillBlack")
        center_layout = QVBoxLayout(center)
        center_layout.setContentsMargins(22, 0, 22, 0)
        lbl_center = QLabel("Designed and developed by Taha Mahmoodi", center)
        lbl_center.setObjectName("HeaderCenterText")
        lbl_center.setStyleSheet("color: white;")
        lbl_center.setAlignment(Qt.AlignCenter)
        center_layout.addWidget(lbl_center)

        right = QFrame(header)
        right.setObjectName("HeaderPillSand")
        right.setFixedSize(132, 78)
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        lbl_right = QLabel("PIIIX", right)
        lbl_right.setObjectName("BrandLabel")
        lbl_right.setStyleSheet("color: #f95c4b;")
        lbl_right.setAlignment(Qt.AlignCenter)
        right_layout.addWidget(lbl_right)

        row.addWidget(left)
        row.addWidget(center, stretch=1)
        row.addWidget(right)
        return header

    def _build_steps(self) -> QWidget:
        box = QWidget(self)
        row = QHBoxLayout(box)
        row.setContentsMargins(343, 0, 343, 0)
        row.setSpacing(139)
        self.step_frames: list[QFrame] = []

        for idx in range(4):
            frame = QFrame(box)
            frame.setFixedSize(84, 84)
            frame.setObjectName("StepInactive")
            col = QVBoxLayout(frame)
            col.setContentsMargins(0, 0, 0, 0)
            txt = QLabel(str(idx + 1), frame)
            txt.setObjectName("StepText")
            txt.setAlignment(Qt.AlignCenter)
            col.addWidget(txt)
            self.step_frames.append(frame)
            row.addWidget(frame)

        return box

    def _build_step1(self) -> QWidget:
        page = QWidget(self)
        outer = QVBoxLayout(page)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(24)

        title = QLabel("Please Select the Libraries You Want to Download", page)
        title.setObjectName("HeaderTitle")
        title.setAlignment(Qt.AlignHCenter)
        outer.addWidget(title)

        middle = QWidget(page)
        grid = QGridLayout(middle)
        grid.setContentsMargins(326, 0, 326, 0)
        grid.setHorizontalSpacing(69)

        providers_box = QWidget(middle)
        providers_layout = QVBoxLayout(providers_box)
        providers_layout.setContentsMargins(0, 0, 0, 0)
        providers_layout.setSpacing(6)
        for provider_id, label, recommended, enabled in PROVIDERS:
            check = QCheckBox(label, providers_box)
            check.setObjectName("ProviderCheck")
            check.setChecked(recommended and enabled)
            check.setEnabled(enabled)
            if enabled and provider_id != "font_face":
                check.stateChanged.connect(self._on_provider_selection_changed)
            self._provider_checks[provider_id] = check
            providers_layout.addWidget(check)
        providers_layout.addStretch(1)

        actions_box = QWidget(middle)
        actions_layout = QVBoxLayout(actions_box)
        actions_layout.setContentsMargins(0, 0, 0, 0)
        actions_layout.setSpacing(6)

        self.select_all = QCheckBox("Select All", actions_box)
        self.select_all.setObjectName("ControlCheck")
        self.select_all.stateChanged.connect(self._on_select_all_changed)
        self.select_recommended = QCheckBox("Select Recommended", actions_box)
        self.select_recommended.setObjectName("ControlCheck")
        self.select_recommended.stateChanged.connect(self._on_select_recommended_changed)

        est_title = QLabel("Estimated Size & Time", actions_box)
        est_title.setObjectName("BodyText")
        est_line = QFrame(actions_box)
        est_line.setFrameShape(QFrame.HLine)
        est_line.setStyleSheet("background: black; min-height: 2px; max-height: 2px;")
        self.estimate_size = QLabel("Size: ~50GB", actions_box)
        self.estimate_size.setObjectName("BodyText")
        self.estimate_time = QLabel("Time: ~1.30 Hour", actions_box)
        self.estimate_time.setObjectName("BodyText")

        actions_layout.addWidget(self.select_all)
        actions_layout.addWidget(self.select_recommended)
        actions_layout.addSpacing(207)
        actions_layout.addWidget(est_title)
        actions_layout.addWidget(est_line)
        actions_layout.addWidget(self.estimate_size)
        actions_layout.addWidget(self.estimate_time)
        actions_layout.addStretch(1)

        grid.addWidget(providers_box, 0, 0)
        grid.addWidget(actions_box, 0, 1)
        outer.addWidget(middle, stretch=1)
        return page

    def _build_step2(self) -> QWidget:
        page = QWidget(self)
        outer = QVBoxLayout(page)
        outer.setContentsMargins(520, 0, 520, 0)
        outer.setSpacing(20)

        title = QLabel("Where Should The Libraries Be Saved", page)
        title.setObjectName("HeaderTitle")
        title.setAlignment(Qt.AlignHCenter)
        outer.addWidget(title)

        dir_title = QLabel("Directory", page)
        dir_title.setObjectName("SectionTitle")
        outer.addWidget(dir_title)

        dir_row = QHBoxLayout()
        self.downloads_root_input = QLineEdit(page)
        self.downloads_root_input.setMinimumHeight(41)
        browse = QPushButton("Choose", page)
        browse.setObjectName("TinyButton")
        browse.setFixedSize(61, 26)
        browse.clicked.connect(self._browse_download_root)
        dir_row.addWidget(self.downloads_root_input, stretch=1)
        dir_row.addWidget(browse)
        outer.addLayout(dir_row)

        folder_title = QLabel("Folder Name", page)
        folder_title.setObjectName("SectionTitle")
        outer.addWidget(folder_title)

        self.base_folder_input = QLineEdit(page)
        self.base_folder_input.setMinimumHeight(41)
        outer.addWidget(self.base_folder_input)
        outer.addStretch(1)
        return page
    def _build_step3(self) -> QWidget:
        page = QWidget(self)
        outer = QHBoxLayout(page)
        outer.setContentsMargins(208, 0, 208, 0)
        outer.setSpacing(136)

        left = QWidget(page)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(16)

        title = QLabel("Download and Extraction", left)
        title.setObjectName("HeaderTitle")
        left_layout.addWidget(title)

        self.fetch_title = QLabel("Fetching Information", left)
        self.fetch_title.setObjectName("SectionTitle")
        self.fetch_bar = QProgressBar(left)
        self.fetch_bar.setRange(0, 100)
        self.fetch_info = QLabel("Info: waiting", left)
        self.fetch_info.setObjectName("MutedText")
        self.fetch_status = QLabel("Status: waiting", left)
        self.fetch_status.setObjectName("MutedText")

        self.download_title = QLabel("Downloading", left)
        self.download_title.setObjectName("SectionTitle")
        self.download_bar = QProgressBar(left)
        self.download_bar.setRange(0, 100)
        self.download_info = QLabel("Info: waiting", left)
        self.download_info.setObjectName("MutedText")
        self.download_status = QLabel("Status: waiting", left)
        self.download_status.setObjectName("MutedText")

        self.extract_title = QLabel("Extracting", left)
        self.extract_title.setObjectName("SectionTitle")
        self.extract_bar = QProgressBar(left)
        self.extract_bar.setRange(0, 100)
        self.extract_info = QLabel("Info: waiting", left)
        self.extract_info.setObjectName("MutedText")
        self.extract_status = QLabel("Status: waiting", left)
        self.extract_status.setObjectName("MutedText")

        left_layout.addWidget(self.fetch_title)
        left_layout.addWidget(self.fetch_bar)
        left_layout.addWidget(self.fetch_info)
        left_layout.addWidget(self.fetch_status)
        left_layout.addSpacing(10)
        left_layout.addWidget(self.download_title)
        left_layout.addWidget(self.download_bar)
        left_layout.addWidget(self.download_info)
        left_layout.addWidget(self.download_status)
        left_layout.addSpacing(10)
        left_layout.addWidget(self.extract_title)
        left_layout.addWidget(self.extract_bar)
        left_layout.addWidget(self.extract_info)
        left_layout.addWidget(self.extract_status)
        left_layout.addStretch(1)

        right = QWidget(page)
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(8)
        log_title = QLabel("Log", right)
        log_title.setObjectName("BodyText")
        log_title.setAlignment(Qt.AlignHCenter)
        self.log_output = QPlainTextEdit(right)
        self.log_output.setReadOnly(True)
        right_layout.addWidget(log_title)
        right_layout.addWidget(self.log_output, stretch=1)

        outer.addWidget(left, stretch=1)
        outer.addWidget(right, stretch=1)
        return page

    def _build_step4(self) -> QWidget:
        page = QWidget(self)
        outer = QHBoxLayout(page)
        outer.setContentsMargins(208, 0, 208, 0)
        outer.setSpacing(136)

        left = QWidget(page)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(16)

        title = QLabel("Installing The Downloaded Libraries", left)
        title.setObjectName("HeaderTitle")
        left_layout.addWidget(title)

        install_title = QLabel("Installation", left)
        install_title.setObjectName("SectionTitle")
        self.install_bar = QProgressBar(left)
        self.install_bar.setRange(0, 100)
        self.install_info = QLabel("Info: waiting", left)
        self.install_info.setObjectName("MutedText")
        self.install_status = QLabel("Status: waiting", left)
        self.install_status.setObjectName("MutedText")

        left_layout.addWidget(install_title)
        left_layout.addWidget(self.install_bar)
        left_layout.addWidget(self.install_info)
        left_layout.addWidget(self.install_status)
        left_layout.addStretch(1)

        right = QWidget(page)
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(8)
        log_title = QLabel("Log", right)
        log_title.setObjectName("BodyText")
        log_title.setAlignment(Qt.AlignHCenter)
        self.install_log_output = QPlainTextEdit(right)
        self.install_log_output.setReadOnly(True)
        right_layout.addWidget(log_title)
        right_layout.addWidget(self.install_log_output, stretch=1)

        outer.addWidget(left, stretch=1)
        outer.addWidget(right, stretch=1)
        return page

    def _build_footer(self) -> QWidget:
        foot = QWidget(self)
        row = QHBoxLayout(foot)
        row.setContentsMargins(61, 0, 61, 0)
        row.setSpacing(16)

        self.exit_button = QPushButton("Exit", foot)
        self.exit_button.setObjectName("DangerButton")
        self.exit_button.setFixedSize(122, 78)
        self.exit_button.clicked.connect(self.close)

        self.center_controls = QWidget(foot)
        center = QHBoxLayout(self.center_controls)
        center.setContentsMargins(0, 0, 0, 0)
        center.setSpacing(50)

        self.cancel_button = QPushButton("Cancel", foot)
        self.cancel_button.setObjectName("DangerButton")
        self.cancel_button.setFixedSize(163, 78)
        self.cancel_button.clicked.connect(self._cancel_now)

        self.pause_button = QPushButton("Pause", foot)
        self.pause_button.setObjectName("PrimaryButton")
        self.pause_button.setFixedSize(151, 78)
        self.pause_button.clicked.connect(self._toggle_pause)

        center.addWidget(self.cancel_button)
        center.addWidget(self.pause_button)

        self.next_button = QPushButton("Next", foot)
        self.next_button.setObjectName("PrimaryButton")
        self.next_button.setFixedSize(135, 78)
        self.next_button.clicked.connect(self._on_next)

        row.addWidget(self.exit_button)
        row.addStretch(1)
        row.addWidget(self.center_controls)
        row.addStretch(1)
        row.addWidget(self.next_button)
        return foot

    def _restore_settings(self) -> None:
        self.resize(
            int(self._settings.get("window_width", 1240)),
            int(self._settings.get("window_height", 860)),
        )
        self.downloads_root_input.setText(str(self._settings.get("downloads_root", str(Path.home() / "Downloads"))))
        self.base_folder_input.setText(str(self._settings.get("base_folder_name", "BFD Fonts")))

        selected = set(self._settings.get("selected_providers", ["google_fonts"]))
        self._bulk_sync_in_progress = True
        for provider_id, _, _, enabled in PROVIDERS:
            check = self._provider_checks[provider_id]
            if not enabled:
                check.setChecked(False)
                continue
            check.setChecked(provider_id in selected)
        self._bulk_sync_in_progress = False
        self._sync_bulk_selection_state()
        self._recalculate_estimate()

    def _persist_settings(self) -> None:
        selected = [pid for pid, check in self._provider_checks.items() if check.isChecked() and check.isEnabled()]
        save_settings(
            {
                "downloads_root": self.downloads_root_input.text().strip(),
                "base_folder_name": self.base_folder_input.text().strip() or "BFD Fonts",
                "selected_providers": selected,
                "window_width": self.width(),
                "window_height": self.height(),
            }
        )

    def _append_log(self, text: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {text}"
        self.log_output.appendPlainText(line)
        self.install_log_output.appendPlainText(line)
        self.log_output.verticalScrollBar().setValue(self.log_output.verticalScrollBar().maximum())
        self.install_log_output.verticalScrollBar().setValue(self.install_log_output.verticalScrollBar().maximum())

    def _apply_step(self, step_index: int) -> None:
        self._current_step = max(0, min(3, step_index))
        self.page_stack.setCurrentIndex(self._current_step)
        for index, frame in enumerate(self.step_frames):
            frame.setObjectName("StepActive" if index <= self._current_step else "StepInactive")
            frame.style().unpolish(frame)
            frame.style().polish(frame)

        self.center_controls.setVisible(self._current_step >= 2)

        if self._state in {"running", "paused"}:
            self.cancel_button.setEnabled(True)
            self.pause_button.setEnabled(True)
            self.next_button.setEnabled(False)
            self.next_button.setText("Running...")
        else:
            self.cancel_button.setEnabled(False)
            self.pause_button.setEnabled(False)
            self.pause_button.setText("Pause")
            if self._current_step == 0:
                self.next_button.setEnabled(True)
                self.next_button.setText("Next")
            elif self._current_step == 1:
                self.next_button.setEnabled(True)
                self.next_button.setText("Start")
            else:
                self.next_button.setEnabled(False)
                self.next_button.setText("Done")

    def _browse_download_root(self) -> None:
        start = self.downloads_root_input.text().strip() or str(Path.home())
        selected = QFileDialog.getExistingDirectory(self, "Select Download Root", start)
        if selected:
            self.downloads_root_input.setText(selected)

    def _selected_providers(self) -> list[str]:
        return [provider_id for provider_id, check in self._provider_checks.items() if check.isEnabled() and check.isChecked() and provider_id != "font_face"]

    def _recommended_provider_ids(self) -> list[str]:
        return [
            provider_id
            for provider_id, _, recommended, enabled in PROVIDERS
            if enabled and provider_id != "font_face" and recommended
        ]

    def _all_enabled_provider_ids(self) -> list[str]:
        return [provider_id for provider_id, _, _, enabled in PROVIDERS if enabled and provider_id != "font_face"]

    def _sync_bulk_selection_state(self) -> None:
        selected = set(self._selected_providers())
        all_enabled = set(self._all_enabled_provider_ids())
        recommended = set(self._recommended_provider_ids())

        all_selected = bool(all_enabled) and selected == all_enabled
        recommended_selected = bool(recommended) and selected == recommended

        self._bulk_sync_in_progress = True
        self.select_all.setChecked(all_selected)
        self.select_recommended.setChecked((not all_selected) and recommended_selected)
        self._bulk_sync_in_progress = False

    def _format_size_gb(self, value: float) -> str:
        rounded = round(value, 1)
        if abs(rounded - int(rounded)) < 1e-9:
            return f"{int(rounded)}GB"
        return f"{rounded:.1f}GB"

    def _format_time_hours(self, value: float) -> str:
        total_minutes = max(0, int(round(value * 60)))
        hours = total_minutes // 60
        minutes = total_minutes % 60
        return f"{hours}.{minutes:02d} Hour"

    def _recalculate_estimate(self) -> None:
        size_total = 0.0
        time_total = 0.0
        for provider_id in self._selected_providers():
            estimate = PROVIDER_ESTIMATE.get(provider_id, {"size_gb": 0.0, "time_hours": 0.0})
            size_total += float(estimate.get("size_gb", 0.0))
            time_total += float(estimate.get("time_hours", 0.0))

        self.estimate_size.setText(f"Size: ~{self._format_size_gb(size_total)}")
        self.estimate_time.setText(f"Time: ~{self._format_time_hours(time_total)}")

    def _validate_output_inputs(self) -> tuple[Path, str] | None:
        downloads_root = self.downloads_root_input.text().strip()
        if not downloads_root:
            QMessageBox.warning(self, "Directory Required", "Choose a download directory.")
            return None

        root_path = Path(downloads_root).expanduser()
        if root_path.exists() and not root_path.is_dir():
            QMessageBox.warning(self, "Invalid Directory", "Selected path is not a directory.")
            return None

        try:
            root_path.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            QMessageBox.warning(self, "Directory Error", f"Could not create or access directory:\n{exc}")
            return None

        base_folder = (self.base_folder_input.text().strip() or "BFD Fonts").strip()
        if any(ch in base_folder for ch in '<>:"/\\|?*'):
            QMessageBox.warning(self, "Invalid Folder Name", "Folder name contains invalid characters.")
            return None

        self.downloads_root_input.setText(str(root_path))
        self.base_folder_input.setText(base_folder)
        return root_path, base_folder

    def _on_select_all_changed(self, state: int) -> None:
        if self._bulk_sync_in_progress:
            return

        checked = state == Qt.Checked
        self._bulk_sync_in_progress = True
        if checked:
            self.select_recommended.setChecked(False)
        for provider_id, check in self._provider_checks.items():
            if provider_id == "font_face":
                continue
            if check.isEnabled():
                check.setChecked(checked)
        self._bulk_sync_in_progress = False
        self._sync_bulk_selection_state()
        self._recalculate_estimate()

    def _on_select_recommended_changed(self, state: int) -> None:
        if self._bulk_sync_in_progress:
            return

        checked = state == Qt.Checked
        self._bulk_sync_in_progress = True
        if checked:
            self.select_all.setChecked(False)
        for provider_id, _, recommended, enabled in PROVIDERS:
            if not enabled or provider_id == "font_face":
                continue
            self._provider_checks[provider_id].setChecked(checked and recommended)
        self._bulk_sync_in_progress = False
        self._sync_bulk_selection_state()
        self._recalculate_estimate()

    def _on_provider_selection_changed(self, _state: int) -> None:
        if self._bulk_sync_in_progress:
            return
        self._sync_bulk_selection_state()
        self._recalculate_estimate()

    def _resource_path(self, relative: Path) -> Path:
        if getattr(sys, "frozen", False):
            base = Path(getattr(sys, "_MEIPASS"))
        else:
            base = Path(__file__).resolve().parent
        return base / relative

    def _create_control_file(self) -> Path:
        path = Path(tempfile.gettempdir()) / f"bfd-control-{uuid.uuid4().hex}.txt"
        path.write_text("", encoding="utf-8")
        return path

    def _worker_path(self) -> Path:
        return self._resource_path(Path("runtime") / "BFD.worker.ps1")

    def _on_next(self) -> None:
        if self._state in {"running", "paused"}:
            return

        if self._current_step == 0:
            if not self._selected_providers():
                QMessageBox.warning(self, "Selection Required", "Select at least one provider.")
                return
            self._apply_step(1)
            return

        if self._current_step == 1:
            self._start_worker()
            return

        if self._current_step in {2, 3} and self._state == "idle":
            self.close()

    def _start_worker(self) -> None:
        if self._state != "idle":
            return

        providers = self._selected_providers()
        if not providers:
            QMessageBox.warning(self, "Selection Required", "Select at least one provider.")
            return

        validated = self._validate_output_inputs()
        if validated is None:
            return

        root_path, base_folder = validated
        worker = self._worker_path()
        if not worker.exists():
            QMessageBox.critical(self, "Worker Missing", f"Worker script not found: {worker}")
            return

        self._control_file = self._create_control_file()
        self._cancel_requested = False
        self._state = "running"
        self._phase = "download"
        self._stdout_buffer = ""
        self._stderr_buffer = ""

        self.fetch_bar.setValue(0)
        self.download_bar.setValue(0)
        self.extract_bar.setValue(0)
        self.install_bar.setValue(0)
        self.fetch_info.setText("Info: waiting")
        self.fetch_status.setText("Status: waiting")
        self.download_info.setText("Info: waiting")
        self.download_status.setText("Status: waiting")
        self.extract_info.setText("Info: waiting")
        self.extract_status.setText("Status: waiting")
        self.install_info.setText("Info: waiting")
        self.install_status.setText("Status: waiting")
        self.log_output.clear()
        self.install_log_output.clear()

        self._apply_step(2)
        self._append_log("Starting BFD worker.")

        args = [
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(worker),
            "-DownloadsRoot",
            str(root_path),
            "-BaseFolderName",
            base_folder,
            "-InstallScope",
            "currentuser",
            "-ControlFilePath",
            str(self._control_file),
            "-EmitGuiEvents",
        ]
        args.extend(["-MethodOrder", "direct", "api", "html"])
        args.append("-Providers")
        args.extend(providers)

        self._process.start("powershell.exe", args)
        if not self._process.waitForStarted(6000):
            self._state = "idle"
            self._append_log("Failed to start worker process.")
            self._apply_step(1)
            return

    def _toggle_pause(self) -> None:
        if self._state not in {"running", "paused"}:
            return

        pid = int(self._process.processId())
        if pid <= 0:
            return

        if self._state == "running":
            suspend_process_tree(pid)
            self._state = "paused"
            self.pause_button.setText("Resume")
            self._append_log("Paused.")
        else:
            resume_process_tree(pid)
            self._state = "running"
            self.pause_button.setText("Pause")
            self._append_log("Resumed.")

    def _cancel_now(self) -> None:
        if self._state not in {"running", "paused"}:
            return

        self._cancel_requested = True
        pid = int(self._process.processId())
        if self._state == "paused" and pid > 0:
            resume_process_tree(pid)
            self._state = "running"
            self.pause_button.setText("Pause")

        if self._control_file:
            try:
                self._control_file.write_text("stop\n", encoding="utf-8")
            except OSError:
                pass

        self._append_log("Cancel requested. Waiting for worker to stop...")
        if not self._process.waitForFinished(4000):
            if pid > 0:
                terminate_process_tree(pid)
            self._process.kill()

    def _on_stdout(self) -> None:
        raw = bytes(self._process.readAllStandardOutput())
        if raw:
            self._stdout_buffer += raw.decode("utf-8", errors="replace")
            self._stdout_buffer = self._consume_buffer(self._stdout_buffer, is_error=False)

    def _on_stderr(self) -> None:
        raw = bytes(self._process.readAllStandardError())
        if raw:
            self._stderr_buffer += raw.decode("utf-8", errors="replace")
            self._stderr_buffer = self._consume_buffer(self._stderr_buffer, is_error=True)

    def _consume_buffer(self, buffer: str, is_error: bool) -> str:
        normalized = buffer.replace("\r\n", "\n").replace("\r", "\n")
        parts = normalized.split("\n")
        for line in parts[:-1]:
            self._handle_line(line, is_error)
        return parts[-1] if parts else ""

    def _handle_line(self, raw_line: str, is_error: bool) -> None:
        line = raw_line.strip()
        if not line:
            return

        parsed: GuiEvent | None = parse_gui_event_line(line)
        if parsed is not None:
            self._handle_event(parsed)
            return

        prefix = "ERR" if is_error else "OUT"
        self._append_log(f"[{prefix}] {line}")

    def _handle_event(self, event: GuiEvent) -> None:
        p = event.payload
        if event.name == "status":
            message = str(p.get("message", "")).strip()
            if message:
                self._append_log(message)
            return

        if event.name == "provider_started":
            provider_name = str(p.get("providerName", "Provider"))
            index = int(float(p.get("index", 0)))
            total = int(float(p.get("total", 0)))
            self.fetch_bar.setValue(0)
            self.download_bar.setValue(0)
            self.extract_bar.setValue(0)
            self.fetch_info.setText(f"{provider_name} ({index}/{total})")
            self.download_info.setText("Info: waiting")
            self.extract_info.setText("Info: waiting")
            self.fetch_status.setText("Status: On going")
            self.download_status.setText("Status: waiting")
            self.extract_status.setText("Status: waiting")
            return

        if event.name == "provider_attempt":
            provider_name = str(p.get("providerName", "Provider"))
            method = str(p.get("method", ""))
            if method:
                self._append_log(f"{provider_name}: trying {method}")
            return

        if event.name == "provider_completed":
            provider_name = str(p.get("providerName", "Provider"))
            status = str(p.get("status", "unknown"))
            font_count = int(float(p.get("fontCount", 0)))
            self.fetch_bar.setValue(100)
            self.download_bar.setValue(100)
            self.extract_bar.setValue(100)
            self._append_log(f"{provider_name} completed [{status}] fonts={font_count}")
            return

        if event.name == "stage_progress":
            stage = str(p.get("stage", "")).lower()
            percent = max(0, min(100, int(float(p.get("percent", 0)))))
            message = str(p.get("message", ""))
            status_text = "Status: Done" if percent >= 100 else "Status: On going"
            if stage == "fetch":
                self.fetch_bar.setValue(percent)
                if message:
                    self.fetch_info.setText(message)
                self.fetch_status.setText(status_text)
            elif stage == "download":
                self.download_bar.setValue(percent)
                if message:
                    self.download_info.setText(message)
                self.download_status.setText(status_text)
            elif stage == "extract":
                self.extract_bar.setValue(percent)
                if message:
                    self.extract_info.setText(message)
                self.extract_status.setText(status_text)
            if message:
                self._append_log(message)
            return

        if event.name == "phase_changed":
            if str(p.get("phase", "")) == "installation":
                self._phase = "installation"
                self._apply_step(3)
                self._append_log("Installation phase started.")
            return

        if event.name == "download_completed":
            self._last_output_folder = str(p.get("outputFolder", "")).strip()
            self.fetch_bar.setValue(100)
            self.download_bar.setValue(100)
            self.extract_bar.setValue(100)
            self.fetch_status.setText("Status: Done")
            self.download_status.setText("Status: Done")
            self.extract_status.setText("Status: Done")
            self._append_log("Download phase completed.")
            return

        if event.name == "install_progress":
            self._apply_step(3)
            percent = max(0, min(100, int(float(p.get("percent", 0)))))
            font = str(p.get("font", ""))
            current = int(float(p.get("current", 0)))
            total = int(float(p.get("total", 0)))
            self.install_bar.setValue(percent)
            self.install_status.setText("Status: Done" if percent >= 100 else "Status: On going")
            if total > 0:
                self.install_info.setText(f"Installing {font} ({current}/{total})")
            elif font:
                self.install_info.setText(f"Installing {font}")
            return

        if event.name == "install_completed":
            self.install_bar.setValue(100)
            self.install_info.setText(str(p.get("message", "Installation complete.")))
            self.install_status.setText("Status: Done")
            self._append_log("Installation completed.")
            return

        if event.name == "completed":
            outcome = str(p.get("outcome", "success"))
            self._last_output_folder = str(p.get("outputFolder", self._last_output_folder)).strip()
            if outcome == "success":
                self._append_log("BFD completed successfully.")
                if self.install_bar.value() == 0 and self._phase != "installation":
                    self.install_info.setText("Installation skipped.")
            elif outcome == "stopped":
                if self._cancel_requested:
                    self._append_log("BFD canceled by user.")
                else:
                    self._append_log("BFD stopped by user.")
            else:
                self._append_log(f"BFD outcome: {outcome}")
            return

        if event.name == "failed":
            self._append_log("Failed: " + str(p.get("message", "Unknown failure")))

    def _on_finished(self, exit_code: int, _status: QProcess.ExitStatus) -> None:
        if self._stdout_buffer:
            self._handle_line(self._stdout_buffer, is_error=False)
            self._stdout_buffer = ""
        if self._stderr_buffer:
            self._handle_line(self._stderr_buffer, is_error=True)
            self._stderr_buffer = ""

        if exit_code == 0:
            self._append_log("Process finished successfully.")
        elif exit_code == 2:
            self._append_log("Process stopped.")
        else:
            self._append_log(f"Process finished with exit code {exit_code}.")

        self._state = "idle"
        self._cancel_requested = False
        self.pause_button.setText("Pause")
        if self._current_step < 2:
            self._apply_step(2)
        else:
            self._apply_step(self._current_step)

        if self._control_file and self._control_file.exists():
            self._control_file.unlink(missing_ok=True)
        self._control_file = None

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        if self._state in {"running", "paused"}:
            answer = QMessageBox.question(
                self,
                "BFD",
                "A run is active. Cancel and close?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer != QMessageBox.Yes:
                event.ignore()
                return
            self._cancel_now()

        self._persist_settings()
        super().closeEvent(event)


def main() -> int:
    app = QApplication(sys.argv)
    app.setFont(QFont("Geologica", 10))
    win = BfdWizardWindow()
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
