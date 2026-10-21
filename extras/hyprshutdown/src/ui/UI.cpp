#include "UI.hpp"
#include "../helpers/Logger.hpp"
#include "../state/AppState.hpp"
#include "../state/HyprlandIPC.hpp"

#include <algorithm>

#include <hyprtoolkit/core/Output.hpp>
#include <hyprtoolkit/types/SizeType.hpp>
#include <hyprutils/memory/SharedPtr.hpp>
#include <hyprutils/os/Process.hpp>

using namespace Hyprutils::OS;

namespace {
    using namespace Hyprtoolkit;
    constexpr float kRowHeight = 54.F;
    constexpr float kRowGap = 6.F;
    constexpr float kMaxCardWidth = 520.F;

    // Text elements parse markup. Window titles and app classes are untrusted text.
    std::string plainMarkup(std::string_view input) {
        std::string result;
        result.reserve(input.size());
        for (const unsigned char character : input) {
            switch (character) {
                case '&': result += "&amp;"; break;
                case '<': result += "&lt;"; break;
                case '>': result += "&gt;"; break;
                case '\"': result += "&quot;"; break;
                case '\'': result += "&apos;"; break;
                default:
                    // Flatten control characters to keep every entry on one line.
                    result += character < 0x20 || character == 0x7f ? ' ' : static_cast<char>(character);
                    break;
            }
        }
        return result;
    }

    SP<CTextElement> textLine(std::string text, float height, float size, float alpha = 1.F) {
        return CTextBuilder::begin()
            ->text(std::move(text))
            ->color([alpha] {
                auto color = g_ui->backend()->getPalette()->m_colors.text;
                color.a *= alpha;
                return color;
            })
            ->fontSize({CFontSize::HT_FONT_ABSOLUTE, size})
            ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {1.F, height}})
            ->noEllipsize(false)
            ->async(false)
            ->commence();
    }

    SP<CNullElement> spacer(float height) {
        return CNullBuilder::begin()
            ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {1.F, height}})
            ->commence();
    }

    template <typename OnClick>
    SP<CButtonElement> actionButton(std::string label, OnClick&& onClick) {
        return CButtonBuilder::begin()
            ->label(std::move(label))
            ->fontSize({CFontSize::HT_FONT_ABSOLUTE, 13.F})
            ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {0.485F, 40.F}})
            ->ellipsize(true)
            ->noBorder(true)
            ->onMainClick(std::forward<OnClick>(onClick))
            ->commence();
    }
}

CUI::CUI()  = default;
CUI::~CUI() = default;

CMonitorState::SAppListApp::SAppListApp(const std::string_view& clazz, const std::string_view& title) {
    using namespace Hyprtoolkit;
    m_null = CRectangleBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {1.F, kRowHeight}})
        ->color([] {
            auto color = g_ui->backend()->getPalette()->m_colors.alternateBase;
            color.a *= 0.65F;
            return color;
        })
        ->rounding(12)
        ->borderThickness(0)
        ->commence();
    m_layout = CColumnLayoutBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_PERCENT, {1.F, 1.F}})
        ->gap(0)
        ->commence();
    m_layout->setMargin(8);

    const auto appName = clazz.empty() ? (title.empty() ? std::string_view{"Anwendung"} : title) : clazz;
    m_class = textLine(plainMarkup(appName), title.empty() || title == appName ? 38.F : 20.F, 12.F);
    m_layout->addChild(m_class);
    if (!title.empty() && title != appName) {
        m_title = textLine(plainMarkup(title), 18.F, 10.F, 0.65F);
        m_layout->addChild(m_title);
    }
    m_null->addChild(m_layout);
}

CMonitorState::CMonitorState(SP<Hyprtoolkit::IOutput> output) : m_monitorName(output->port()) {
    using namespace Hyprtoolkit;
    m_window = CWindowBuilder::begin()
                   ->type(HT_WINDOW_LAYER)
                   ->prefferedOutput(output)
                   ->anchor(0xF)
                   ->layer(3)
                   ->preferredSize({0, 0})
                   ->exclusiveZone(-1)
                   ->appClass("hyprshutdown")
                   ->commence();

    m_bg = CRectangleBuilder::begin()
               ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_PERCENT, {1, 1}})
               ->color([] {
                   auto color = g_ui->backend()->getPalette()->m_colors.background;
                   color.a *= 0.94F;
                   return color;
               })
               ->commence();

    m_card = CRectangleBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_ABSOLUTE, CDynamicSize::HT_SIZE_ABSOLUTE, {kMaxCardWidth, 240.F}})
        ->color([] { return g_ui->backend()->getPalette()->m_colors.base; })
        ->rounding(28)
        ->borderThickness(1)
        ->borderColor([] {
            auto color = g_ui->backend()->getPalette()->m_colors.text;
            color.a *= 0.10F;
            return color;
        })
        ->commence();
    m_card->setPositionMode(IElement::HT_POSITION_ABSOLUTE);
    m_card->setPositionFlag(IElement::HT_POSITION_FLAG_CENTER, true);

    m_layout = CColumnLayoutBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_PERCENT, {1.F, 1.F}})
        ->gap(0)
        ->commence();
    m_layout->setMargin(24);

    m_topText = textLine("<b>" + plainMarkup(g_ui->m_shutdownLabel.empty() ? "Abmelden …" : g_ui->m_shutdownLabel) + "</b>", 36.F, 22.F);
    m_subText = textLine("Apps werden geschlossen", 20.F, 12.F, 0.68F);
    m_forceNote = textLine("Erzwingen kann ungespeicherte Arbeit verwerfen.", 18.F, 10.F, 0.57F);

    m_appListScroll = CScrollAreaBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {1.F, kRowHeight}})
        ->scrollY(true)
        ->scrollX(false)
        ->showScrollbar(false)
        ->commence();
    m_appListLayout = CColumnLayoutBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_AUTO, {1.F, 1.F}})
        ->gap(static_cast<size_t>(kRowGap))
        ->commence();

    m_buttonLayout = CRowLayoutBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {1.F, 40.F}})
        ->gap(0)
        ->commence();
    auto buttonGap = CNullBuilder::begin()
        ->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {0.03F, 1.F}})
        ->commence();

    m_forceQuit = actionButton("Erzwingen", [](auto) {
        State::state()->killAllApps();
        g_ui->exit(true);
    });
    m_cancel = actionButton("Abbrechen", [](auto) { g_ui->exit(false); });
    m_cancel->rebuild()->accent(true)->commence();
    m_buttonLayout->addChild(m_cancel);
    m_buttonLayout->addChild(buttonGap);
    m_buttonLayout->addChild(m_forceQuit);

    m_window->m_rootElement->addChild(m_bg);
    m_window->m_rootElement->addChild(m_card);
    m_card->addChild(m_layout);
    m_appListScroll->addChild(m_appListLayout);
    m_layout->addChild(m_topText);
    m_layout->addChild(m_subText);
    m_layout->addChild(spacer(14.F));
    m_layout->addChild(m_appListScroll);
    m_layout->addChild(spacer(14.F));
    m_layout->addChild(m_forceNote);
    m_layout->addChild(spacer(10.F));
    m_layout->addChild(m_buttonLayout);

    m_resizeListener = m_window->m_events.resized.listen([this](Hyprutils::Math::Vector2D size) { updateGeometry(size); });
    update();
    m_window->open();
}

void CMonitorState::updateGeometry(const Hyprutils::Math::Vector2D& logicalSize) {
    using namespace Hyprtoolkit;
    if (logicalSize.x > 1 && logicalSize.y > 1)
        m_logicalSize = logicalSize;

    const float padding = m_logicalSize.x < 420.F ? 18.F : 24.F;
    const float width = std::max(1.F, std::min(kMaxCardWidth, static_cast<float>(m_logicalSize.x) - 32.F));
    // Fixed header/footer plus a naturally sized viewport, capped at four app rows.
    constexpr float fixedContentHeight = 152.F;
    const float chromeHeight = fixedContentHeight + padding * 2.F;
    const float rowCount = static_cast<float>(std::min<size_t>(4, m_apps.size()));
    const float desiredListHeight = rowCount > 0 ? rowCount * kRowHeight + (rowCount - 1.F) * kRowGap : 0.F;
    const float availableHeight = std::max(1.F, static_cast<float>(m_logicalSize.y) - 32.F);
    const float listHeight = std::max(0.F, std::min(desiredListHeight, availableHeight - chromeHeight));
    const float height = std::min(availableHeight, chromeHeight + listHeight);

    m_layout->setMargin(padding);
    m_card->rebuild()->size({CDynamicSize::HT_SIZE_ABSOLUTE, CDynamicSize::HT_SIZE_ABSOLUTE, {width, height}})->commence();
    m_appListScroll->rebuild()->size({CDynamicSize::HT_SIZE_PERCENT, CDynamicSize::HT_SIZE_ABSOLUTE, {1.F, listHeight}})
        ->scrollY(desiredListHeight < static_cast<float>(m_apps.size()) * (kRowHeight + kRowGap) - kRowGap || listHeight < desiredListHeight)
        ->commence();
}

void CMonitorState::update() {
    m_apps.clear();
    m_appListLayout->clearChildren();
    const auto& apps = State::state()->apps();
    for (const auto& app : apps) {
        m_apps.emplace_back(makeUnique<SAppListApp>(app->m_class, app->m_title));
        m_appListLayout->addChild(m_apps.back()->m_null);
    }
    updateGeometry(m_logicalSize);
}

void CUI::registerOutput(const SP<Hyprtoolkit::IOutput>& mon) {
    m_states.emplace_back(makeUnique<CMonitorState>(mon));
    mon->m_events.removed.listenStatic([this, m = WP<Hyprtoolkit::IOutput>{mon}] { std::erase_if(m_states, [&m](const auto& e) { return e->m_monitorName == m->port(); }); });
}

void CUI::exit(bool closeHl) {
    g_ui->m_states.clear();

    g_ui->backend()->addIdle([this, closeHl] {
        g_ui->m_backend->destroy();
        g_ui->m_backend.reset();

        if (closeHl && !m_noExit && !State::state()->m_dryRun) {
            //NOLINTNEXTLINE
            std::string cmd = State::state()->m_useLua ? "/dispatch hl.dsp.exit()" : "/dispatch exit";
            HyprlandIPC::getFromSocket(cmd);
            if (m_postExitCmd) {
                CProcess proc("/bin/sh", {"-c", m_postExitCmd.value()});
                proc.runAsync();
            }
        }
    });
}

void CUI::setTimer() {
    // every 5 seconds or so, attempt to sigterm apps again
    static uint16_t          counter     = 0;
    constexpr const uint16_t COUNTER_MAX = 30;

    m_updateTimer = m_backend->addTimer(
        std::chrono::milliseconds(150),
        [this](ASP<Hyprtoolkit::CTimer> timer, void* d) {
            if (State::state()->apps().empty()) {
                exit(true);
                return;
            }

            counter++;

            if (counter > COUNTER_MAX) {
                g_logger->log(LOG_DEBUG, "Re-closing apps");
                counter = 0;
                State::state()->reexitApps();
            }

            if (!State::state()->updateState()) {
                setTimer();
                return; // no changes
            }

            for (const auto& s : m_states) {
                s->update();
            }

            setTimer();
        },
        nullptr);
}

bool CUI::run() {
    auto data           = Hyprtoolkit::IBackend::SBackendCreationData();
    data.pLogConnection = makeShared<Hyprutils::CLI::CLoggerConnection>(*g_logger);
    data.pLogConnection->setName("hyprtoolkit");
    data.pLogConnection->setLogLevel(LOG_DEBUG);
    m_backend = Hyprtoolkit::IBackend::createWithData(data);

    if (!m_backend)
        return false;

    {
        const auto MONITORS = m_backend->getOutputs();

        for (const auto& m : MONITORS) {
            registerOutput(m);
        }

        m_listeners.newMon = m_backend->m_events.outputAdded.listen([this](SP<Hyprtoolkit::IOutput> mon) { registerOutput(mon); });

        g_logger->log(LOG_DEBUG, "Found {} output(s)", MONITORS.size());

        setTimer();
    }

    m_backend->enterLoop();

    return true;
}

SP<Hyprtoolkit::IBackend> CUI::backend() {
    return m_backend;
}
