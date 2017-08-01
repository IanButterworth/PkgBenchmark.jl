# Run a function after loading a REQUIREs file.
# Clean up afterwards
function _with_reqs(f, reqs::AbstractString, pre = () -> nothing)
    if isfile(reqs)
        _with_reqs(f, Pkg.Reqs.parse(reqs), pre)
    else
        f()
    end
end

function _with_reqs(f, reqs::Dict, pre = () -> nothing)
    pre()
    cd(Pkg.dir()) do
        Pkg.Entry.resolve(merge(Pkg.Reqs.parse("REQUIRE"), reqs))
    end
    try f() catch ex rethrow() finally cd(Pkg.Entry.resolve, Pkg.dir()) end
end


function _withtemp(f, file)
    try f(file)
    catch err
        rethrow()
    finally rm(file; force = true) end
end


# Runs a function at a commit on a repo and afterwards goes back
# to the original commit / branch.
function _withcommit(f, repo, commit)
    LibGit2.transact(repo) do r
        branch = try LibGit2.branch(r) catch err; nothing end
        prev = _shastring(r, "HEAD")
        try
            LibGit2.checkout!(r, _shastring(r, commit))
            f()
        catch err
            rethrow(err)
        finally
            if branch !== nothing
                LibGit2.branch!(r, branch)
            end
        end
    end
end

_shastring(r::LibGit2.GitRepo, refname) = string(LibGit2.revparseid(r, refname))
_shastring(dir::AbstractString, refname) = LibGit2.with(r -> _shastring(r, refname), LibGit2.GitRepo(dir))

function _get_julia_commit(config = BenchmarkConfig())
    str = """println("__JULIA_COMMIT_START", Base.GIT_VERSION_INFO.commit, "__JULIA_COMMIT_END")"""
    res = try
        String(read(`$(config.juliacmd[1]) --startup-file=no -e $str`))
    catch
        error("Failed to get commit for julia using command $(config.juliacmd[1])")
    end
    juliacommit = split(split(res, "__JULIA_COMMIT_START")[2], "__JULIA_COMMIT_END")[1]
end

_benchinfo(str) = print_with_color(Base.info_color(), STDOUT, "PkgBenchmark: ", str, "\n")
_benchwarn(str) = print_with_color(Base.info_color(), STDOUT, "PkgBenchmark: ", str, "\n")


############
# Markdown #
############

_idrepr(id) = (str = repr(id); str[searchindex(str, '['):end])
_intpercent(p) = string(ceil(Int, p * 100), "%")
_resultrow(ids, t::BenchmarkTools.Trial) = _resultrow(ids, minimum(t))

function _resultrow(ids, t::BenchmarkTools.TrialEstimate)
    t_tol = _intpercent(BenchmarkTools.params(t).time_tolerance)
    m_tol = _intpercent(BenchmarkTools.params(t).memory_tolerance)
    timestr = BenchmarkTools.time(t) == 0 ? "" : string(BenchmarkTools.prettytime(BenchmarkTools.time(t)), " (", t_tol, ")")
    memstr = BenchmarkTools.memory(t) == 0 ? "" : string(BenchmarkTools.prettymemory(BenchmarkTools.memory(t)), " (", m_tol, ")")
    gcstr = BenchmarkTools.gctime(t) == 0 ? "" : BenchmarkTools.prettytime(BenchmarkTools.gctime(t))
    allocstr = BenchmarkTools.allocs(t) == 0 ? "" : string(BenchmarkTools.allocs(t))
    return "| `$(_idrepr(ids))` | $(timestr) | $(gcstr) | $(memstr) | $(allocstr) |"
end


function _resultrow(ids, t::BenchmarkTools.TrialJudgement)
    t_tol = _intpercent(BenchmarkTools.params(t).time_tolerance)
    m_tol = _intpercent(BenchmarkTools.params(t).memory_tolerance)
    t_ratio = @sprintf("%.2f", BenchmarkTools.time(BenchmarkTools.ratio(t)))
    m_ratio =  @sprintf("%.2f", BenchmarkTools.memory(BenchmarkTools.ratio(t)))
    t_mark = _resultmark(BenchmarkTools.time(t))
    m_mark = _resultmark(BenchmarkTools.memory(t))
    timestr = "$(t_ratio) ($(t_tol)) $(t_mark)"
    memstr = "$(m_ratio) ($(m_tol)) $(m_mark)"
    return "| `$(_idrepr(ids))` | $(timestr) | $(memstr) |"
end

_resultmark(sym::Symbol) = sym == :regression ? _REGRESS_MARK : (sym == :improvement ? _IMPROVE_MARK : "")

const _REGRESS_MARK = ":x:"
const _IMPROVE_MARK = ":white_check_mark:"