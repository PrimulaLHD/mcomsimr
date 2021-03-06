#' Simulate Metacommunity Dynamics
#'
#' @param patches number of patches to simulate
#' @param species number of species to simulate
#' @param dispersal dispersal probability between 0 and 0.5
#' @param plot option to show plot of landscape
#' @param torus whether to model the landscape as a torus
#' @param kernel_exp the exponential rate at which dispersal decreases as a function of the distance between patches
#' @param env1Scale scale of environmental autocorrelation between 0 and 1000
#' @param timesteps number of timesteps to simulate
#' @param burn_in length of burn in period
#' @param initialization length of initial period before environmental change begins
#' @param max_r intrinsic growth rate in optimal environment, can be single value or vector of length species
#' @param min_env minium environmental optima
#' @param max_env minium environmental optima
#' @param env_niche_breadth standard deviation of environmental niche breadth, can be single value or vector of length species
#' @param optima_spacing "even" or "random" to specify how optima should be distributed
#' @param intra intraspecific competition coefficient, single value or vector of length species
#' @param min_inter min interspecific comp. coefficient
#' @param max_inter max interspecific comp. coefficient
#' @param comp_scaler value to multiply all competition coefficients by
#' @param extirp_prob probability of local extirpation for each population in each time step (should be a very small value, e.g. 0 or 0.002)
#'
#' @param landscape optional dataframe with x and y columns for patch coordinates
#' @param disp_mat optional matrix with each column specifying the probability that an individual disperses to each other patch (row)
#' @param env.df optional dataframe with environmental conditions with columns: env1, patch, time
#' @param env_optima optional values of environmental optima, should be a vector of length species
#' @param int_matrix optional externally generated competition matrix

#' @return list that includes metacommunity dynamics, landscape coordinates, environmental conditions, species environmental traits, dispersal matrix, and the competition matrix
#'
#' @author Patrick L. Thompson, \email{patrick.thompson@@zoology.ubc.ca}
#'
#' @examples
#' simulate_MC(patches = 6, species = 10, dispersal = 0.001, min_inter = 1, max_inter = 1, env_niche_breadth = 10)

#'
#' @import ggplot2
#' @import dplyr
#'
#' @export
#'
simulate_MC <- function(patches, species, dispersal = 0.01,
                        plot = TRUE,
                        torus=TRUE, kernel_exp = 0.1,
                        env1Scale = 500, timesteps = 1500, burn_in = 500, initialization = 200,
                        max_r = 5, min_env = 0, max_env = 1, env_niche_breadth = 0.5, optima_spacing = "random",
                        intra = 1, min_inter = 0, max_inter = 1.5, comp_scaler = 0.05,
                        extirp_prob = 0,
                        landscape, disp_mat, env.df, env_optima, int_mat){
  if (missing(landscape)){
    landscape <- landscape_generate(patches = patches, plot = plot)
  } else {
    landscape <- landscape_generate(patches = patches, xy = landscape, plot = plot)
  }

  if (missing(disp_mat)){
    disp_mat <- dispersal_matrix(landscape = landscape,torus = torus, kernel_exp = kernel_exp, plot = plot)
  } else {
    disp_mat <- dispersal_matrix(landscape = landscape, disp_mat = disp_mat, torus = torus, kernel_exp = kernel_exp, plot = plot)
  }

  if (missing(env.df)){
    env.df <- env_generate(landscape = landscape, env1Scale = env1Scale, timesteps = timesteps+burn_in, plot = plot)
  } else {
    env.df <- env_generate(landscape = landscape, env.df = env.df, env1Scale = env1Scale, timesteps = timesteps+burn_in, plot = plot)
  }

  if (missing(env_optima)){
    env_traits.df <- env_traits(species = species, max_r = max_r, min_env = min_env, max_env = max_env, env_niche_breadth = env_niche_breadth, optima_spacing = optima_spacing, plot = plot)
  } else {
    env_traits.df <- env_traits(species = species, max_r = max_r, min_env = min_env, max_env = max_env, env_niche_breadth = env_niche_breadth, optima_spacing = optima_spacing, optima = env_optima, plot = plot)
  }

  if (missing(int_mat)){
    int_mat <- species_int_mat(species = species, intra = intra, min_inter = min_inter, max_inter = max_inter, comp_scaler = comp_scaler, plot = TRUE)
  } else {
    int_mat <- species_int_mat(species = species, int_matrix = int_mat, intra = intra, min_inter = min_inter, max_inter = max_inter, comp_scaler = comp_scaler, plot = TRUE)
  }

  dynamics.df <- data.frame()
  N <- matrix(rpois(n = species*patches, lambda = 0.5), nrow = patches, ncol = species)
  pb <- txtProgressBar(min = 0, max = initialization + burn_in + timesteps, style = 3)
  for(i in 1:(initialization + burn_in + timesteps)){
   if(i <= initialization){
     if(i %in% seq(10,100, by = 10)){
       N <- N + matrix(rpois(n = species*patches, lambda = 0.5), nrow = patches, ncol = species)
     }
     env <- env.df$env1[env.df$time == 1]
   } else {
     env <- env.df$env1[env.df$time == (i-initialization)]
   }
    r <- max_r*exp(-(t((env_traits.df$optima - matrix(rep(env, each = species), nrow = species, ncol = patches))/(2*env_traits.df$env_niche_breadth)))^2)
    N_hat <- N*r/(1+N%*%int_mat)
    N_hat[N_hat < 0] <- 0
    N_hat <- matrix(rpois(n = species*patches, lambda = N_hat), ncol = species, nrow = patches)

    E <- matrix(rpois(n = species*patches, lambda = dispersal*N_hat), ncol = species, nrow = patches)
    I <- matrix(rpois(n = species*patches, lambda = disp_mat%*%E), ncol = species, nrow = patches)

    N <- N_hat - E + I
    N[rbinom(n = species * patches, size = 1, prob = extirp_prob)>0] <- 0

    dynamics.df <- rbind(dynamics.df, data.frame(N = c(N), patch = 1:patches, species = rep(1:species, each = patches), env = env, time = i-initialization-burn_in))
    setTxtProgressBar(pb, i)
  }
  close(pb)
  dynamics.df <- left_join(dynamics.df, env_traits.df)
  env.df$time_run <- env.df$time - burn_in

  env.df_init <- data.frame(env1 = env.df$env1[env.df$time == 1], patch = 1:patches, time = NA, time_run = rep(seq(-(burn_in + initialization), -burn_in, by = 1), each = patches))
  env.df <- rbind(env.df_init,env.df)

  if(plot == TRUE){
    sample_patches <- sample(1:patches, size = min(c(patches,6)), replace = FALSE)
    g <- dynamics.df %>%
      filter(time %in% seq(min(dynamics.df$time),max(dynamics.df$time), by =10)) %>%
      filter(patch %in% sample_patches) %>%
      ggplot(aes(x = time, y = N, group = species, color = optima))+
      geom_line()+
      facet_wrap(~patch)+
      scale_color_viridis_c()+
      geom_path(data = filter(env.df, patch %in% sample_patches), aes(y = -5, x = time_run, color = env1, group = NULL), size = 3)

    print(g)
  }

  return(list(dynamics.df = dynamics.df, landscape = landscape, env.df = env.df, env_traits.df = env_traits.df, disp_mat = disp_mat, int_mat = int_mat))
}
