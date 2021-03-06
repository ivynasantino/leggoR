source(here::here("R/utils.R"))
source(here::here("R/agendas.R"))
senado_env <- jsonlite::fromJSON(here::here("R/config/environment_senado.json"))
senado_constants <- senado_env$constants

#' @title Retorna o dataFrame com as audiências públicas do Senado
#' @description Retorna um dataframe contendo as audiências públicas do Senado
#' @param initial_date data inicial no formato yyyy-mm-dd
#' @param end_date data final no formato yyyy-mm-dd
#' @return Dataframe
#' @examples
#' get_audiencias_publicas('2016-05-15', '2016-05-25')
get_audiencias_publicas <- function(initial_date, end_date) {

  pega_audiencias_publicas_do_data_frame <- function(l){
    if(length(l$Tipo) == 1 ) {
      if (l$Tipo == "Audiência Pública Interativa") {
        paste(l$Eventos$Evento$MateriasRelacionadas$Materia$Codigo, collapse = " ,")
      }else {
        ""
      }
    }else {
      if ("Audiência Pública Interativa" %in% l$Tipo) {
        paste(l$Eventos$Evento$MateriasRelacionadas, collapse = " ,")
      }else {
        ""
      }
    }
  }

  agenda_senado <- get_data_frame_agenda_senado(initial_date, end_date) %>%
    dplyr::mutate(id_proposicao = purrr::map_chr(partes_parte, ~ pega_audiencias_publicas_do_data_frame(.)))

  if ("comissoes_comissao_sigla" %in% names(agenda_senado)) {
    agenda_senado %>%
      dplyr::select(data, hora, realizada, sigla = comissoes_comissao_sigla, id_proposicao)
  }else {
    agenda_senado %>%
      mutate(sigla = purrr::map_chr(comissoes_comissao, ~ paste(.$Sigla, collapse = " ,"))) %>%
      dplyr::select(data, hora, realizada, sigla, id_proposicao)
  }
}

#' @title Baixa a agenda de audiências públicas na câmara por órgão
#' @description Retorna um dataframe contendo as audiências públicas da camara ou do senado
#' @param initial_date data inicial no formato dd/mm/yyyy
#' @param end_date data final no formato dd/mm/yyyy
#' @param fases_tramitacao_df dataframe da PL preprocessada
#' @return Dataframe com as audiências públicas de um órgão
#' @examples
#' fetch_audiencias_publicas_by_orgao_camara('01/01/2017', '30/10/2018', process_proposicao(fetch_proposicao(2121442, 'camara', 'Lei do Teto Remuneratório', 'Agenda Nacional'), fetch_tramitacao(2121442, 'camara', T), 'camara'))
#' @importFrom dplyr filter
#' @importFrom dplyr select
#' @importFrom dplyr if_else
#' @importFrom dplyr mutate
#' @importFrom stringr str_detect
#' @importFrom stringr str_extract_all
#' @importFrom tidyr unnest
#' @importFrom tibble tibble
#' @importFrom utils tail
#' @importFrom lubridate as_date
fetch_audiencias_publicas_by_orgao_camara <- function(initial_date, end_date, fases_tramitacao_df){
  orgao_atual <-
    fases_tramitacao_df %>%
    dplyr::filter(data_hora >= lubridate::as_date(lubridate::dmy(initial_date)) &
                    data_hora <= lubridate::as_date((lubridate::dmy(end_date))) &
                    sigla_local != 'MESA' &
                    sigla_local != 'PLEN') %>%
    utils::tail(1) %>%
    dplyr::mutate(local =
                    dplyr::if_else(toupper(local) == "PLENÁRIO", "PLEN", dplyr::if_else(local == 'Comissão Especial',
                                                                                        sigla_local,
                                                                                        local))) %>%
    dplyr::distinct() %>%
    dplyr::select(local) %>%
    dplyr::rename(sigla = local)

  if(nrow(orgao_atual) > 0){
    orgao_id <-
      fetch_orgaos_camara() %>%
      dplyr::filter(stringr::str_detect(sigla, orgao_atual$sigla)) %>%
      dplyr::select(orgao_id)


    url <- RCurl::getURL(paste0(
      'http://www.camara.leg.br/SitCamaraWS/Orgaos.asmx/ObterPauta?IDOrgao=',
      orgao_id$orgao_id, '&datIni=', initial_date, '&datFim=', end_date))

    eventos_list <- readXML(url)

    df <-
      eventos_list %>%
      jsonlite::toJSON() %>%
      jsonlite::fromJSON()

    if(purrr::is_list(df)){
      df <- df %>%
        purrr::list_modify(".attrs" = NULL) %>%
        tibble::as.tibble() %>%
        t() %>%
        as.data.frame()

      names(df) <- c("comissao","cod_reuniao", "num_reuniao", "data", "hora", "local",
                     "estado", "tipo", "titulo_reuniao", "objeto", "proposicoes")

      df <- df %>%
        dplyr::filter (tipo == 'Audiência Pública') %>%
        dplyr::select(-c(num_reuniao, proposicoes)) %>%
        as.data.frame() %>%
        sapply( function(x) unlist(x)) %>%
        as.data.frame()

      #df <- df %>%
      #  dplyr::mutate(proposicao = stringr::str_extract(tolower(objeto), '"discussão d(o|a) (pl|projeto de lei) .*"'),
      #                tipo_materia = dplyr::case_when(
      #                  stringr::str_detect(tolower(proposicao), 'pl| projeto de lei') ~ 'PL',
      #                  TRUE ~ 'NA'),
      #                numero_aux = stringr::str_extract(tolower(proposicao), "(\\d*.|)\\d* de"),
      #                numero = stringr::str_extract(tolower(numero_aux), "(\\d*.|)\\d*"),
      #                numero = gsub('\\.', '', numero),
      #                ano_aux = stringr::str_extract(tolower(proposicao), "( de |/)\\d*"),
      #                ano = stringr::str_extract(tolower(ano_aux), "\\d{4}|\\d{2}")) %>%
      #  dplyr::select(-ano_aux, -numero_aux, -proposicao,  -tipo)

      df <- df %>%
        dplyr::mutate(requerimento =
                        stringr::str_extract_all(tolower(objeto),
                                                 camara_env$frase_requerimento$requerimento),
                      num_requerimento =
                        dplyr::if_else(
                          stringr::str_extract_all(
                            requerimento, camara_env$extract_requerimento_num$regex) != 'character(0)',
                          stringr::str_extract_all(
                            requerimento, camara_env$extract_requerimento_num$regex) %>% lapply(function(x)(preprocess_requerimentos(x))),
                          list(0))) %>%
        dplyr::select(-requerimento)

      return(df)

    }
  }
  return (tibble::frame_data(~ comissao, ~ cod_reuniao, ~ data, ~ hora, ~ local,
                             ~ estado, ~ tipo_materia, ~ titulo_reuniao, ~ objeto, ~ numero, ~ ano))

}

preprocess_requerimentos <- function(element){
  element <- dplyr::if_else(
    stringr::str_detect(element, stringr::regex('/[0-9]{4}')),
    sub('/[0-9]{2}', '/', element),
    element)

  element <- gsub(" ","", element)

  return (element)
}

readXML <- function(url) {
  out <- tryCatch({
    XML::xmlParse(url) %>%
      XML::xmlToList()
  },
  error=function(cond) {
    message(paste("Request returned Error 503 Service Unavailable. Please try again later."))
    return(NA)
  },
  warning=function(cond) {
    message(paste("Request caused a warning:", url))
    message(cond)
    return(NULL)
  }
  )
  return(out)
}
