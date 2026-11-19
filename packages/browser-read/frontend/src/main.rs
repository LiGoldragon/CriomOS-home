use datom_codec::{Actualizing, Budget, Composing, Datomizable, Path, Potential};
use protos::{Protosizable, ReaderBudget, Textualizable};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    fs,
    io::Write,
    process::{Command, Stdio},
};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Composing, Datomizable, Serialize, Deserialize)]
struct PageName(String);
#[derive(Clone, Debug, PartialEq, Eq, Hash, Composing, Datomizable, Serialize, Deserialize)]
struct FieldName(String);
#[derive(Composing, Datomizable)]
struct ReadRequest {
    page: PageName,
    fields: Vec<FieldName>,
}
#[derive(Composing, Datomizable)]
enum Input {
    Read(ReadRequest),
}
#[derive(Clone, Composing, Datomizable, Serialize)]
struct Milliseconds(i64);
#[derive(Clone, Composing, Datomizable, Serialize)]
struct ByteCount(i64);
#[derive(Clone, Composing, Datomizable, Serialize)]
struct PageAddress(String);
#[derive(Clone, Composing, Datomizable, Serialize)]
struct FieldLocator(String);
#[derive(Clone, Composing, Datomizable, Serialize)]
struct Limits {
    navigation_ms: Milliseconds,
    action_ms: Milliseconds,
    command_ms: Milliseconds,
    cleanup_ms: Milliseconds,
    output_bytes: ByteCount,
}
#[derive(Clone, Composing, Datomizable, Serialize)]
struct Field {
    name: FieldName,
    locator: FieldLocator,
}
#[derive(Composing, Datomizable)]
struct Page {
    name: PageName,
    url: PageAddress,
    fields: Vec<Field>,
}
#[derive(Composing, Datomizable)]
struct Registry {
    limits: Limits,
    pages: Vec<Page>,
}
#[derive(Composing, Datomizable)]
enum Configuration {
    Registry(Registry),
}
#[derive(Serialize)]
struct ReadTask {
    url: PageAddress,
    fields: Vec<Field>,
    limits: Limits,
}
#[derive(Composing, Datomizable, Deserialize)]
#[serde(deny_unknown_fields)]
struct FieldValue {
    name: FieldName,
    value: String,
}
#[derive(Composing, Datomizable, Deserialize)]
enum Refusal {
    InvalidRequest,
    MissingRegistry,
    UnreadableRegistry,
    InvalidRegistry,
    UnknownPage(PageName),
    UnknownFields(Vec<FieldName>),
    SessionAttach,
    TabOpen,
    Navigation,
    Fields(Vec<FieldName>),
    TabCleanup,
    SessionRun,
    SessionCleanup,
    ArtifactSetup,
    ArtifactCleanup,
    BrowserOutcome,
    Interrupted,
}
#[derive(Composing, Datomizable)]
enum Output {
    Read(Vec<FieldValue>),
    Refused(Refusal),
}
#[derive(Deserialize)]
#[serde(tag = "phase", deny_unknown_fields)]
enum Observation {
    Read { values: Vec<FieldValue> },
    Refused { refusal: Refusal },
}
#[derive(Serialize)]
struct WrapperRequest<'a> {
    #[serde(rename = "readCode")]
    read_code: String,
    limits: &'a Limits,
}
#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
enum WrapperReply {
    Returned {
        result: String,
    },
    Refused {
        #[serde(rename = "isError")]
        is_error: bool,
        phase: Refusal,
    },
}

// Contracts precede their implementations: typed text, registry selection, and
// the sole existing-wrapper transport are distinct roles.
trait DatomText: Sized + datom_codec::Composing + Datomizable {
    fn read_text(text: &str) -> Result<Self, ()>;
    fn write_text(&self) -> String;
}
trait RegistrySelection {
    fn select(&self, request: &ReadRequest) -> Result<ReadTask, Refusal>;
}
trait WrapperReading {
    fn read(&self, task: &ReadTask) -> Output;
}
struct Wrapper {
    executable: String,
}
struct Invocation {
    arguments: Vec<String>,
}
trait Invocable {
    fn run(&self) -> Output;
}

impl<T: datom_codec::Composing + Datomizable> DatomText for T {
    fn read_text(text: &str) -> Result<Self, ()> {
        // The input itself bounds the parser's work, rather than a policy limit
        // hidden in code. Both grammars have fixed shallow structural depth.
        let nodes = i64::try_from(text.len()).map_err(|_| ())?.saturating_add(1);
        let mut budget = Budget {
            remaining: nodes,
            reader: ReaderBudget::try_from(usize::try_from(nodes).map_err(|_| ())?)
                .map_err(|_| ())?,
            depth: 0,
            maximum_depth: nodes,
        };
        Potential::from(text).actualize(&mut budget).map_err(|_| ())
    }
    fn write_text(&self) -> String {
        self.datomize(Path::new()).protosize().textualize()
    }
}
impl RegistrySelection for Registry {
    fn select(&self, request: &ReadRequest) -> Result<ReadTask, Refusal> {
        let limits = &self.limits;
        if [
            limits.navigation_ms.0,
            limits.action_ms.0,
            limits.command_ms.0,
            limits.cleanup_ms.0,
            limits.output_bytes.0,
        ]
        .iter()
        .any(|n| *n <= 0)
            // Playwright's driver wait reaches Node's signed-32-bit timer.
            || [limits.navigation_ms.0, limits.action_ms.0, limits.cleanup_ms.0]
                .iter().any(|value| i32::try_from(*value).is_err())
            || limits
                .command_ms
                .0
                .checked_add(limits.cleanup_ms.0)
                .is_none()
        {
            return Err(Refusal::InvalidRegistry);
        }
        let mut names = HashSet::new();
        for page in &self.pages {
            let mut fields = HashSet::new();
            let address: http::Uri = page.url.0.parse().map_err(|_| Refusal::InvalidRegistry)?;
            if !matches!(address.scheme_str(), Some("http" | "https"))
                || address
                    .authority()
                    .is_none_or(|a| a.host().is_empty() || a.as_str().contains('@'))
                || page.url.0.contains('\\')
            {
                return Err(Refusal::InvalidRegistry);
            }
            if page.name.0.is_empty()
                || !names.insert(&page.name)
                || page.fields.iter().any(|f| {
                    f.name.0.is_empty() || f.locator.0.is_empty() || !fields.insert(&f.name)
                })
            {
                return Err(Refusal::InvalidRegistry);
            }
        }
        let page = self
            .pages
            .iter()
            .find(|p| p.name == request.page)
            .ok_or_else(|| Refusal::UnknownPage(request.page.clone()))?;
        let mut missing = Vec::new();
        let mut fields = Vec::new();
        for name in &request.fields {
            match page.fields.iter().find(|field| &field.name == name) {
                Some(field) => fields.push(field.clone()),
                None => missing.push(name.clone()),
            }
        }
        if !missing.is_empty() {
            return Err(Refusal::UnknownFields(missing));
        }
        Ok(ReadTask {
            url: page.url.clone(),
            limits: limits.clone(),
            fields,
        })
    }
}
impl WrapperReading for Wrapper {
    fn read(&self, task: &ReadTask) -> Output {
        let attempt = || -> Result<Output, ()> {
            let data = serde_json::to_string(task).map_err(|_| ())?;
            let code = format!(
                "async page => {{ const module = {{exports:{{}}}}; {}; return await module.exports.readPage(page,{}); }}",
                include_str!("read-page.cjs"),
                data
            );
            let request = WrapperRequest {
                read_code: code,
                limits: &task.limits,
            };
            let serialized = serde_json::to_vec(&request).map_err(|_| ())?;
            // One call and one terminal reply. The reviewed wrapper alone owns
            // timeouts, process lifetimes, private artifacts and cleanup.
            let mut child = Command::new(&self.executable)
                .arg("read-session")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|_| ())?;
            let written = child.stdin.take().ok_or(())?.write_all(&serialized);
            let reply = child.wait_with_output().map_err(|_| ())?;
            written.map_err(|_| ())?;
            let wrapper: WrapperReply = serde_json::from_slice(&reply.stdout).map_err(|_| ())?;
            let observed: Observation = match wrapper {
                WrapperReply::Refused {
                    is_error: true,
                    phase,
                } => {
                    return match phase {
                        Refusal::SessionAttach
                        | Refusal::SessionRun
                        | Refusal::SessionCleanup
                        | Refusal::ArtifactSetup
                        | Refusal::ArtifactCleanup
                        | Refusal::Interrupted => Ok(Output::Refused(phase)),
                        _ => Err(()),
                    };
                }
                WrapperReply::Refused { .. } => return Err(()),
                WrapperReply::Returned { result } => {
                    serde_json::from_str(&result).map_err(|_| ())?
                }
            };
            match observed {
                Observation::Read { values } => {
                    if !reply.status.success()
                        || values.len() != task.fields.len()
                        || values
                            .iter()
                            .zip(&task.fields)
                            .any(|(v, f)| v.name != f.name)
                    {
                        return Err(());
                    }
                    Ok(Output::Read(values))
                }
                Observation::Refused { refusal } => match refusal {
                    Refusal::Fields(ref fields)
                        if fields.is_empty()
                            || fields.iter().collect::<HashSet<_>>().len() != fields.len()
                            || fields
                                .iter()
                                .any(|name| !task.fields.iter().any(|f| &f.name == name)) =>
                    {
                        Err(())
                    }
                    Refusal::TabOpen
                    | Refusal::Navigation
                    | Refusal::Fields(_)
                    | Refusal::TabCleanup => Ok(Output::Refused(refusal)),
                    _ => Err(()),
                },
            }
        };
        attempt().unwrap_or(Output::Refused(Refusal::BrowserOutcome))
    }
}
impl Invocable for Invocation {
    fn run(&self) -> Output {
        let run = || -> Result<Output, Refusal> {
            let [executable, registry, request] = self.arguments.as_slice() else {
                return Err(Refusal::InvalidRequest);
            };
            let Input::Read(request) =
                Input::read_text(request).map_err(|_| Refusal::InvalidRequest)?;
            if request.page.0.is_empty()
                || request.fields.is_empty()
                || request.fields.iter().any(|f| f.0.is_empty())
                || request.fields.iter().collect::<HashSet<_>>().len() != request.fields.len()
            {
                return Err(Refusal::InvalidRequest);
            }
            let text = fs::read_to_string(registry).map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    Refusal::MissingRegistry
                } else {
                    Refusal::UnreadableRegistry
                }
            })?;
            let Configuration::Registry(configuration) =
                Configuration::read_text(&text).map_err(|_| Refusal::InvalidRegistry)?;
            let task = configuration.select(&request)?;
            Ok(Wrapper {
                executable: executable.clone(),
            }
            .read(&task))
        };
        run().unwrap_or_else(Output::Refused)
    }
}
fn main() {
    let output = Invocation {
        arguments: std::env::args().skip(1).collect(),
    }
    .run();
    println!("{}", output.write_text());
    if matches!(output, Output::Refused(_)) {
        std::process::exit(1);
    }
}
