#' Remove type annotations from a file
#'
#' @param input A character string; the path of the input.
#' @param output A character string; the path of the output.
#'
#' @examples
#' file <- system.file('example/test_3.R', package = "typeChecker")
#' invisible(Map(cat, readLines(file), "\n"))
#' remove_types_from_file(file)
#'
#' @export
remove_types_from_file <- function(input, output = stdout()) {
    src_file <- readLines(input)

    src_comment_line_num <- src_file %>%
        has_full_comment() %>%
        which()

    src_exprs_line_num <- parse(input) %>%
        attr("srcref") %>%
        purrr::map(~.x[c(1, 3)]) # first line and last line, see ?srcfile

    # Remove the type annotation
    new_exprs <- file(input) %>%
        rlang::parse_exprs() %>%
        purrr::map(types::remove_types) %>%
        purrr::map(deparse)

    # Create a new file with the annotation-free expressions
    res <- new_exprs %>%
        purrr::map2(src_exprs_line_num, function(expr, lnum) {
            # Turn a new expression into a block of the same length as the
            # original expression
            res <- rep("", lnum[2])
            write_lines <- setdiff(lnum[1]:lnum[2], src_comment_line_num)
            if (length(write_lines) != length(expr)) {
                stop("The length of the replacement does not match with the original.")
            }
            res[write_lines] <- expr
            res[lnum[1]:lnum[2]]
        }) %>%
        purrr::reduce2(src_exprs_line_num, function(res, expr, lnum) {
            # Insert the blocks into an empty file following the layout in the
            # original file
            res[lnum[1]:lnum[2]] <- expr
            res
        }, .init = rep("", length(src_file))) %>%
        # Insert comments at the exact same position as the original file
        purrr::map2_chr(trailing_comment(src_file), safe_paste)

    writeLines(res, con = output)
}


has_full_comment <- Vectorize(function(x) {
    substring(trimws(x), 1, 1) == "#"
})


trailing_comment <- Vectorize(function(x) {
    chars <- x
    pos <- 1
    while (nchar(chars) > 0) {
        char <- substring(chars, 1, 1)
        if (char == '"') {
            m <- chars %>%
                # Reference: https://stackoverflow.com/questions/2039795/regular-expression-for-a-string-literal-in-flex-lex
                regexpr('"(\\\\.|[^\\\"])*"', ., perl = T) %>%
                attr("match.length")
            chars <- substring(chars, 1 + m)
            pos <- pos + m
        } else if (char == "'") {
            m <- chars %>%
                regexpr("'(\\\\.|[^\\\'])*'", ., perl = T) %>%
                attr("match.length")
            chars <- substring(chars, 1 + m)
            pos <- pos + m
        } else if (char == "#") {
            return(list(start_pos = pos, text = chars))
        } else {
            chars <- substring(chars, 2)
            pos <- pos + 1
        }
    }
    NULL
})

safe_paste <- function(x, y) {
    if (is.null(y)) return(x)
    if (nchar(x) >= y$start_pos) {
        stop(sprintf("The character at position %d has been occupied", y$start_pos))
    }
    paddings <- paste(rep(" ", y$start_pos - 1 - nchar(x)), collapse = "")
    paste0(x, paddings, y$text)
}
