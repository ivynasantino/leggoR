#' @title Retorna o dataFrame da agenda do Senado
#' @description Retorna um dataframe contendo a agenda do senado
#' @param initial_date data inicial no formato yyyy-mm-dd
#' @param end_date data final no formato yyyy-mm-dd
#' @return Dataframe
#' @examples
#' get_data_frame_agenda_senado('2016-05-15', '2016-05-25')
get_data_frame_agenda_senado <- function(initial_date, end_date) {
  url <-
    paste0("http://legis.senado.leg.br/dadosabertos/agenda/", gsub('-','', initial_date), "/", gsub('-','', end_date), "/detalhe")
  json_proposicao <- fetch_json_try(url)
  
  json_proposicao$Reunioes$Reuniao %>%
    tibble::as.tibble() %>%
    rename_table_to_underscore() %>%
    dplyr::filter(situacao != 'Cancelada')
}

#' @title Normaliza as agendas da câmara ou do senado
#' @description Retorna um dataframe contendo a agenda da camara ou do senado normalizada
#' @param agenda dataframe com agenda
#' @param house camara ou senado
#' @return Dataframe
#' @examples
#' normalize_agendas(fetch_agenda_camara('2018-09-03', '2018-09-07'), 'camara')
normalize_agendas <- function(agenda, house) {
  if (tolower(house) == 'senado') {
    if (nrow(agenda$materias) == 0) {return(agenda$materias)}
    materias <- agenda$materias
    agenda <- agenda$agenda
    agenda <-
      merge(agenda, materias) %>%
      dplyr::mutate(sigla = paste0(sigla_materia, " ", numero_materia, "/", ano_materia))
    
    if (!("local_sessao" %in% names(agenda))) {
      agenda <-
        agenda %>%
        dplyr::mutate(local_sessao = NA)
    }
    
    agenda <-
      agenda %>%
      dplyr::select(c(data, sigla, codigo_materia, local_sessao))
    
  }else {
    if (nrow(agenda) == 0) {return(tibble::frame_data(~ data, ~ sigla, ~ id_proposicao, ~ local))}
    agenda <-
      agenda %>%
      dplyr::mutate(sigla = paste0(proposicao_.siglaTipo, " ", proposicao_.numero, "/", proposicao_.ano)) %>%
      dplyr::select(c(hora_inicio, sigla, proposicao_.id, nome_orgao))
  }
  
  new_names <- c("data", "sigla", "id_proposicao", "local")
  names(agenda) <- new_names
  
  agenda %>% dplyr::arrange(data)
}

#' @title Baixa a agenda da câmara ou do senado
#' @description Retorna um dataframe contendo a agenda da camara ou do senado
#' @param initial_date data inicial no formato yyyy-mm-dd
#' @param end_date data final no formato yyyy-mm-dd
#' @param house camara ou senado
#' @param orgao plenario ou comissoes
#' @return Dataframe
#' @examples
#' fetch_agenda('2018-07-03', '2018-07-10', 'camara', 'comissoes')
#' @export
fetch_agenda <- function(initial_date, end_date, house, orgao) {
  try(if (as.Date(end_date) < as.Date(initial_date))
    stop("A data inicial é depois da final!"))
  
  if (tolower(orgao) == "plenario") {
    if (house == "camara") {
      normalize_agendas(
        rcongresso::fetch_agenda_camara(
          initial_date = initial_date, end_date = end_date), house)
    } else {
      normalize_agendas(rcongresso::fetch_agenda_senado(initial_date), house)
    }
  }else {
    if(house == 'camara') {
      initial_date <- strsplit(initial_date, '-')
      end_date <- strsplit(end_date, '-')
      fetch_agenda_comissoes_camara(
        paste0(initial_date[[1]][[3]],'/', initial_date[[1]][[2]], '/', initial_date[[1]][[1]]),
        paste0(end_date[[1]][[3]],'/', end_date[[1]][[2]], '/', end_date[[1]][[1]]))
    }else {
      rcongresso::fetch_agenda_senado_comissoes(initial_date, end_date)
    }
  }
}

#' @title Baixa a agenda da camara e do senado
#' @description Retorna um dataframe contendo a agenda geral da camara e do
#' senado
#' @param initial_date data inicial no formato yyyy-mm-dd
#' @param end_date data final no formato yyyy-mm-dd
#' @return Dataframe
#' @examples
#' fetch_agenda_geral('2018-07-03', '2018-07-10')
#' @export
fetch_agenda_geral <- function(initial_date, end_date) {
  try(if(as.Date(end_date) < as.Date(initial_date)) stop("A data inicial é depois da final!"))
  print(initial_date)
  print(end_date)
  
  agenda_plenario_camara <- normalize_agendas(rcongresso::fetch_agenda_camara(initial_date = initial_date, end_date = end_date), "camara") %>%
    dplyr::mutate(casa = "camara")
  
  if (nrow(agenda_plenario_camara) != 0) {
    agenda_plenario_camara <-
      agenda_plenario_camara %>%
      dplyr::rowwise() %>%
      dplyr::mutate(data = stringr::str_split(data,'T')[[1]][1]) %>%
      dplyr::ungroup()
  }
  agenda_plenario_senado <-
    normalize_agendas(rcongresso::fetch_agenda_senado(initial_date), "senado") %>%
    dplyr::mutate(casa = "senado")
  agenda_comissoes_senado <- rcongresso::fetch_agenda_senado_comissoes(initial_date, end_date) %>%
    dplyr::mutate(data = as.character(data)) %>%
    dplyr::mutate(casa = "senado")

  initial_date <- strsplit(as.character(initial_date), '-')
  end_date <- strsplit(as.character(end_date), '-')
  agenda_comissoes_camara <-
    fetch_agenda_comissoes_camara(
      paste0(initial_date[[1]][[3]],'/', initial_date[[1]][[2]], '/', initial_date[[1]][[1]]),
      paste0(end_date[[1]][[3]],'/', end_date[[1]][[2]], '/', end_date[[1]][[1]])) %>%
    dplyr::mutate(data = as.character(data)) %>%
    dplyr::mutate(casa = "camara")
  
  rbind(
    agenda_plenario_camara,
    agenda_plenario_senado,
    agenda_comissoes_senado,
    agenda_comissoes_camara
  ) %>%
    dplyr::arrange(data) %>%
    dplyr::mutate_all(as.character) %>%
    dplyr::rename(id_ext = id_proposicao)
}

#' @title Baixa dados da agenda de um orgão da Camara
#' @description Retorna um dataframe contendo dados sobre a agenda de um orgão da camara
#' @param orgao_id ID do orgão
#' @param initial_date data inicial no formato dd/mm/yyyy
#' @param end_date data final no formato dd/mm/yyyy
#' @return Dataframe
#' @importFrom RCurl getURL
fetch_agendas_comissoes_camara_auxiliar <- function(orgao_id, initial_date, end_date){
  
  url <-
    RCurl::getURL(paste0(
      'http://www.camara.leg.br/SitCamaraWS/Orgaos.asmx/ObterPauta?IDOrgao=',
      orgao_id, '&datIni=', initial_date, '&datFim=', end_date))
  
  eventos <-
    XML::xmlParse(url) %>%
    XML::xmlToList() %>% 
    jsonlite::toJSON() %>%
    jsonlite::fromJSON()
  
  if(purrr::is_list(eventos)){
    eventos <-
      eventos %>%
      purrr::list_modify(".attrs" = NULL) %>%
      tibble::as.tibble() %>%
      t() %>%
      as.data.frame()
    
    names(eventos) <- c("comissao","cod_reuniao", "num_reuniao", "data", "hora", "local",
                   "estado", "tipo", "titulo_reuniao", "objeto", "proposicoes")
    
    proposicoes <- eventos$proposicoes
    eventos <-
      eventos %>%
      dplyr::select(-c(num_reuniao, objeto, proposicoes)) %>%
      lapply(unlist) %>%
      as.data.frame() %>%
      tibble::add_column(proposicoes)
    
    eventos <-
      eventos %>%
      as.data.frame() %>%
      dplyr::filter(trimws(estado) != 'Cancelada') %>%
      tidyr::unnest()
    
    if(nrow(eventos) != 0) {
      eventos <-
        eventos %>%
        dplyr::mutate(sigla = purrr::map(proposicoes, ~ .x[['sigla']]),
                      id_proposicao = purrr::map(proposicoes, ~ .x[['idProposicao']]))
    }
    
  }else{
    
    eventos <- tibble::frame_data(~ comissao, ~ cod_reuniao, ~ num_reuniao, ~ data, ~ hora, ~ local,
                             ~ estado, ~ tipo, ~ titulo_reuniao, ~ objeto, ~ proposicoes)
  }
  
  return(eventos)
}

#' @title Baixa dados da agenda de todos os orgãos da Camara
#' @description Retorna um dataframe contendo dados sobre a agenda da camara
#' @param initial_date data inicial no formato dd/mm/yyyy
#' @param end_date data final no formato dd/mm/yyyy
#' @return Dataframe
#' @examples
#' fetch_agenda_comissoes_camara('12/05/2018', '26/05/2018')
fetch_agenda_comissoes_camara <- function(initial_date, end_date) {
  orgaos <- rcongresso::fetch_orgaos_camara()
  
  agenda <- purrr::map_df(orgaos$orgao_id, fetch_agendas_comissoes_camara_auxiliar, initial_date, end_date)
  
  if (nrow(agenda) == 0) {
    tibble::frame_data(~ data, ~ sigla, ~ id_proposicao, ~ local)
  } else {
    agenda %>%
      dplyr::select(data, sigla, id_proposicao, local = comissao) %>%
      dplyr::mutate(data = as.Date(data, "%d/%m/%Y")) %>%
      dplyr::arrange(data)
  }
}

#' @title Baixa dados da agenda por semana
#' @description Retorna um dataframe contendo dados sobre a agenda
#' @param initial_date data inicial no formato dd/mm/yyyy
#' @param end_date data final no formato dd/mm/yyyy
#' @return Dataframe
#' @examples
#' junta_agendas('2018-11-05', '2018-11-12')
#' @export
junta_agendas <- function(initial_date, end_date) {
  semanas <-
    seq(lubridate::floor_date(as.Date(initial_date), unit="week") + 1, as.Date(end_date), by = "week") %>%
    tibble::as.tibble() %>%
    dplyr::mutate(fim_semana = as.Date(cut(value, "week")) + 4)
  
  materia <- purrr::map2_df(semanas$value, semanas$fim_semana, ~ fetch_agenda_geral(.x, .y))
}