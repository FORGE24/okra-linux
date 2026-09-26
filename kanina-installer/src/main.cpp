#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QGroupBox>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QProgressBar>
#include <QPushButton>
#include <QStackedWidget>
#include <QVBoxLayout>
#include <QWidget>

#include <QDir>
#include <QProcess>

class Installer final : public QWidget {
public:
    Installer() {
        setWindowTitle(QStringLiteral("Kanina Installer"));
        showFullScreen();

        auto *root = new QVBoxLayout(this);
        auto *title = new QLabel(QStringLiteral("Install OkraLinux Base OS 0"));
        title->setStyleSheet(QStringLiteral("font-size: 24px; font-weight: bold;"));
        root->addWidget(title);

        pages = new QStackedWidget;
        pages->addWidget(buildWelcome());
        pages->addWidget(buildTarget());
        pages->addWidget(buildUser());
        pages->addWidget(buildConfirm());
        pages->addWidget(buildProgress());
        root->addWidget(pages, 1);

        auto *buttons = new QHBoxLayout;
        back = new QPushButton(QStringLiteral("Back"));
        next = new QPushButton(QStringLiteral("Next"));
        buttons->addWidget(back);
        buttons->addStretch();
        buttons->addWidget(next);
        root->addLayout(buttons);
        connect(back, &QPushButton::clicked, this, [this] { pages->setCurrentIndex(qMax(0, pages->currentIndex() - 1)); });
        connect(next, &QPushButton::clicked, this, [this] { advance(); });
        updateButtons();
    }

private:
    QStackedWidget *pages{};
    QPushButton *back{};
    QPushButton *next{};
    QComboBox *disk{};
    QLineEdit *efi{};
    QLineEdit *rootPartition{};
    QLineEdit *hostname{};
    QLineEdit *username{};
    QLineEdit *password{};
    QCheckBox *formatRoot{};
    QPlainTextEdit *summary{};
    QProgressBar *progress{};
    QLabel *status{};

    QWidget *buildWelcome() {
        auto *page = new QWidget;
        auto *layout = new QVBoxLayout(page);
        layout->addWidget(new QLabel(QStringLiteral("Kanina is the graphical installer for OkraLinux Base OS 0.")));
        layout->addWidget(new QLabel(QStringLiteral("This installer uses manual partition selection and installs the current LiveCD root filesystem.\nBackup important data before continuing.")));
        layout->addStretch();
        return page;
    }

    QWidget *buildTarget() {
        auto *page = new QWidget;
        auto *layout = new QVBoxLayout(page);
        auto *box = new QGroupBox(QStringLiteral("Installation target"));
        auto *form = new QFormLayout(box);
        disk = new QComboBox;
        disk->addItems(listDisks());
        efi = new QLineEdit;
        rootPartition = new QLineEdit;
        formatRoot = new QCheckBox(QStringLiteral("Format root partition as ext4"));
        formatRoot->setChecked(true);
        form->addRow(QStringLiteral("Disk:"), disk);
        form->addRow(QStringLiteral("EFI partition:"), efi);
        form->addRow(QStringLiteral("Root partition:"), rootPartition);
        form->addRow(QString(), formatRoot);
        layout->addWidget(box);
        layout->addWidget(new QLabel(QStringLiteral("Example: /dev/nvme0n1p1 for EFI and /dev/nvme0n1p2 for root. Existing partitions are never changed until Install is pressed.")));
        layout->addStretch();
        return page;
    }

    QWidget *buildUser() {
        auto *page = new QWidget;
        auto *form = new QFormLayout(page);
        hostname = new QLineEdit(QStringLiteral("okralinux"));
        username = new QLineEdit;
        password = new QLineEdit;
        password->setEchoMode(QLineEdit::Password);
        form->addRow(QStringLiteral("Hostname:"), hostname);
        form->addRow(QStringLiteral("Username:"), username);
        form->addRow(QStringLiteral("Password:"), password);
        return page;
    }

    QWidget *buildConfirm() {
        auto *page = new QWidget;
        auto *layout = new QVBoxLayout(page);
        layout->addWidget(new QLabel(QStringLiteral("Review your installation choices:")));
        summary = new QPlainTextEdit;
        summary->setReadOnly(true);
        layout->addWidget(summary);
        return page;
    }

    QWidget *buildProgress() {
        auto *page = new QWidget;
        auto *layout = new QVBoxLayout(page);
        status = new QLabel;
        progress = new QProgressBar;
        layout->addWidget(status);
        layout->addWidget(progress);
        layout->addStretch();
        return page;
    }

    QStringList listDisks() const {
        QStringList result;
        QDir dir(QStringLiteral("/sys/block"));
        for (const auto &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (!name.startsWith(QStringLiteral("loop")) && !name.startsWith(QStringLiteral("ram")) && !name.startsWith(QStringLiteral("sr")))
                result << QStringLiteral("/dev/") + name;
        }
        return result;
    }

    void advance() {
        const int index = pages->currentIndex();
        if (index == 1 && (efi->text().isEmpty() || rootPartition->text().isEmpty())) {
            QMessageBox::warning(this, QStringLiteral("Missing partition"), QStringLiteral("Select both an EFI partition and a root partition."));
            return;
        }
        if (index == 2 && (username->text().isEmpty() || password->text().isEmpty())) {
            QMessageBox::warning(this, QStringLiteral("Missing account"), QStringLiteral("Enter a username and password."));
            return;
        }
        if (index == 2 && summary != nullptr) {
            summary->setPlainText(QStringLiteral("Disk: %1\nEFI: %2\nRoot: %3\nFormat root: %4\nHostname: %5\nUser: %6\nBootloader: Limine")
                .arg(disk->currentText(), efi->text(), rootPartition->text(), formatRoot->isChecked() ? QStringLiteral("yes") : QStringLiteral("no"), hostname->text(), username->text()));
        }
        if (index == 3) {
            if (QMessageBox::warning(this, QStringLiteral("Confirm installation"), QStringLiteral("The selected root partition may be formatted. Continue?"), QMessageBox::Yes | QMessageBox::No) != QMessageBox::Yes)
                return;
            pages->setCurrentIndex(4);
            next->setEnabled(false);
            back->setEnabled(false);
            runInstall();
            return;
        }
        pages->setCurrentIndex(qMin(pages->count() - 1, index + 1));
        updateButtons();
    }

    void runInstall() {
        status->setText(QStringLiteral("Preparing installation..."));
        progress->setRange(0, 0);
        QStringList args{QStringLiteral("--disk"), disk->currentText(), QStringLiteral("--efi"), efi->text(), QStringLiteral("--root"), rootPartition->text(), QStringLiteral("--hostname"), hostname->text(), QStringLiteral("--user"), username->text(), QStringLiteral("--password-stdin")};
        if (formatRoot->isChecked()) args << QStringLiteral("--format-root");
        auto *process = new QProcess(this);
        connect(process, &QProcess::readyReadStandardError, this, [this, process] { status->setText(QString::fromLocal8Bit(process->readAllStandardError()).trimmed()); });
        connect(process, &QProcess::finished, this, [this, process](int code) {
            progress->setRange(0, 1);
            progress->setValue(code == 0 ? 1 : 0);
            status->setText(code == 0 ? QStringLiteral("Installation complete. Reboot to start OkraLinux.") : QStringLiteral("Installation failed. Check the log output."));
            next->setText(QStringLiteral("Close"));
            next->setEnabled(true);
            connect(next, &QPushButton::clicked, qApp, &QApplication::quit, Qt::UniqueConnection);
            process->deleteLater();
        });
        connect(process, &QProcess::started, this, [this, process] {
            process->write(password->text().toUtf8());
            process->write("\n");
            process->closeWriteChannel();
        });
        process->start(QStringLiteral("/usr/libexec/kanina-install"), args);
    }

    void updateButtons() {
        const int index = pages->currentIndex();
        back->setEnabled(index > 0 && index < pages->count() - 1);
        next->setText(index == 3 ? QStringLiteral("Install") : QStringLiteral("Next"));
        next->setEnabled(index < 4);
    }
};

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    Installer installer;
    installer.show();
    return app.exec();
}
